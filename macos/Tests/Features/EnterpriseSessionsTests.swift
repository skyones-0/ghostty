import Foundation
import Testing
@testable import Ghostty

@MainActor
struct EnterpriseSessionsTests {

    // MARK: - 1. SavedSession & Connect Command Generation Tests

    @Test func testSavedSessionBasicSSH() {
        let session = SavedSession(name: "Basic Server", host: "192.168.1.100")
        let cmd = session.buildConnectCommand()
        #expect(cmd.contains("ssh"))
        #expect(cmd.contains("-o ControlMaster=auto"))
        #expect(cmd.contains("-o ControlPath=/tmp/spectre-ssh-%C.sock"))
        #expect(cmd.contains("-o ControlPersist=10m"))
        #expect(cmd.contains("192.168.1.100"))
        #expect(!cmd.contains("-p"))
        #expect(!cmd.contains("@"))
    }

    @Test func testSavedSessionFullParameters() {
        let forwards = [
            PortForwardRule(type: .local, localPort: 8080, remoteHost: "127.0.0.1", remotePort: 80),
            PortForwardRule(type: .remote, localPort: 3000, remoteHost: "localhost", remotePort: 9000),
            PortForwardRule(type: .dynamic, localPort: 1080)
        ]

        let session = SavedSession(
            name: "Core Router",
            host: "router.corp.internal",
            user: "admin",
            port: 2222,
            identityFile: "~/.ssh/id_ed25519",
            jumpHost: "bastion.corp.internal",
            forwardAgent: true,
            compression: true,
            keepAliveInterval: 45,
            initialCommand: "show ip route",
            environmentBadge: "PROD",
            portForwards: forwards
        )

        let cmd = session.buildConnectCommand()

        #expect(cmd.contains("admin@router.corp.internal"))
        #expect(cmd.contains("-p 2222"))
        #expect(cmd.contains("-i "))
        #expect(cmd.contains("id_ed25519"))
        #expect(cmd.contains("-J \"bastion.corp.internal\""))
        #expect(cmd.contains("-A"))
        #expect(cmd.contains("-C"))
        #expect(cmd.contains("-o ServerAliveInterval=45"))
        #expect(cmd.contains("-L 8080:127.0.0.1:80"))
        #expect(cmd.contains("-R 9000:localhost:3000"))
        #expect(cmd.contains("-D 1080"))
        #expect(cmd.contains("-t \"show ip route\""))
        #expect(session.environmentBadge == "PROD")
    }

    @Test func testSavedSessionTelnetAndConsole() {
        let telnet = SavedSession(name: "Legacy Switch", host: "10.0.0.1", port: 2323, sessionType: "telnet")
        #expect(telnet.buildConnectCommand() == "telnet 10.0.0.1 2323")

        let serial = SavedSession(name: "Cisco Console", host: "/dev/cu.usbserial-0001", port: 9600, sessionType: "console")
        #expect(serial.buildConnectCommand() == "screen /dev/cu.usbserial-0001 9600")
    }

    @Test func testSavedSessionCodableRoundTrip() throws {
        let original = SavedSession(
            name: "Database Cluster",
            folder: "Databases/Postgres",
            host: "db1.prod",
            user: "postgres",
            port: 54322,
            environmentBadge: "PROD",
            portForwards: [PortForwardRule(type: .local, localPort: 5432, remoteHost: "127.0.0.1", remotePort: 5432)]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SavedSession.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == "Database Cluster")
        #expect(decoded.folder == "Databases/Postgres")
        #expect(decoded.host == "db1.prod")
        #expect(decoded.user == "postgres")
        #expect(decoded.port == 54322)
        #expect(decoded.environmentBadge == "PROD")
        #expect(decoded.portForwards.count == 1)
        #expect(decoded.portForwards[0].sshArgument == "-L 5432:127.0.0.1:5432")
    }

    // MARK: - 2. ActiveSSHContext & SSHTransferManager Tests

    @Test func testActiveSSHContext() {
        let context = ActiveSSHContext(
            host: "server.example.com",
            user: "deployer",
            port: 2200,
            identityFile: "~/.ssh/id_rsa",
            jumpHost: "jump.example.com"
        )

        #expect(context.targetSpec == "deployer@server.example.com")
        let args = context.buildBaseSCPArguments()
        #expect(args.contains("-o"))
        #expect(args.contains("ControlMaster=auto"))
        #expect(args.contains("ControlPath=/tmp/spectre-ssh-%C.sock"))
        #expect(args.contains("-P"))
        #expect(args.contains("2200"))
        #expect(args.contains("-J"))
        #expect(args.contains("jump.example.com"))
    }

    @Test func testSSHTransferManagerRegistration() {
        let manager = SSHTransferManager.shared
        let surfaceId = UUID()
        let session = SavedSession(
            name: "Cloud Node",
            host: "node.cloud.io",
            user: "ubuntu",
            port: 22
        )

        manager.registerContext(for: surfaceId, session: session)
        #expect(manager.hasActiveSSHContext(for: surfaceId) == true)
        let ctx = manager.context(for: surfaceId)
        #expect(ctx != nil)
        #expect(ctx?.host == "node.cloud.io")
        #expect(ctx?.user == "ubuntu")
        #expect(ctx?.targetSpec == "ubuntu@node.cloud.io")
    }

    // MARK: - 3. Keyword Highlighter Engine Tests

    @Test func testKeywordHighlighterDetection() {
        let highlighter = KeywordHighlighter.shared
        highlighter.isEnabled = true

        let sampleTerminalOutput = """
        [12:00:01] Interface GigabitEthernet0/1 is UP, line protocol is UP
        [12:00:02] Connected to 192.168.10.254 via MAC 00:1A:2B:3C:4D:5E
        [12:00:03] BGP neighbor 10.0.0.1 state is ESTABLISHED
        [12:00:04] ERROR: Authentication failed for user guest - DENIED
        [12:00:05] WARNING: CPU temperature high, TIMEOUT detected on node 172.16.0.50
        [12:00:06] CRITICAL: Power supply 2 is DOWN, system PANIC avoided
        """

        highlighter.scan(text: sampleTerminalOutput)

        #expect(highlighter.totalMatchesCount > 0)

        let words = highlighter.detectedMatches.map { $0.text.uppercased() }

        // Validate Error matches
        #expect(words.contains("ERROR"))
        #expect(words.contains("DENIED"))
        #expect(words.contains("CRITICAL"))
        #expect(words.contains("DOWN"))
        #expect(words.contains("PANIC"))

        // Validate Success / Up matches
        #expect(words.contains("UP"))
        #expect(words.contains("ESTABLISHED"))

        // Validate Warning matches
        #expect(words.contains("WARNING"))
        #expect(words.contains("TIMEOUT"))

        // Validate Network IP matches
        let ips = highlighter.detectedMatches.filter { $0.category == .networkIP }.map { $0.text }
        #expect(ips.contains("192.168.10.254"))
        #expect(ips.contains("10.0.0.1"))
        #expect(ips.contains("172.16.0.50"))

        // Validate MAC address matches
        let macs = highlighter.detectedMatches.filter { $0.category == .networkMAC }.map { $0.text }
        #expect(macs.contains("00:1A:2B:3C:4D:5E"))
    }

    @Test func testKeywordHighlighterToggle() {
        let highlighter = KeywordHighlighter.shared
        highlighter.isEnabled = false
        highlighter.scan(text: "ERROR DOWN CRITICAL 192.168.1.1")
        #expect(highlighter.detectedMatches.isEmpty)
        #expect(highlighter.totalMatchesCount == 0)
        highlighter.isEnabled = true
    }

    // MARK: - 4. Forensic Session Logger Tests

    @Test func testSessionLoggerCreationAndANSIStripping() throws {
        let logger = SessionLogger.shared
        let testSessionName = "UnitTest_Logging_\(UUID().uuidString.prefix(6))"

        logger.prependTimestamps = true
        logger.stripANSI = true

        logger.startRecording(sessionName: testSessionName)
        #expect(logger.isRecording == true)
        #expect(logger.currentLogURL != nil)

        // Log ANSI colorized text
        let coloredMessage = "\u{1B}[31m[ERROR]\u{1B}[0m Connection reset by \u{1B}[32m192.168.1.50\u{1B}[0m\n"
        logger.log(text: coloredMessage)

        let logURL = logger.stopRecording()
        #expect(logger.isRecording == false)
        #expect(logURL != nil)

        // Read recorded file
        let fileContent = try String(contentsOf: logURL!, encoding: .utf8)

        // Assert header exists
        #expect(fileContent.contains("=== Spectre Pro Session Log: \(testSessionName) ==="))
        #expect(fileContent.contains("=== Session Ended:"))

        // Assert ANSI sequence was stripped
        #expect(!fileContent.contains("\u{1B}[31m"))
        #expect(!fileContent.contains("\u{1B}[0m"))
        #expect(fileContent.contains("[ERROR] Connection reset by 192.168.1.50"))

        // Assert timestamps were prepended
        #expect(fileContent.contains("[202"))

        // Clean up test log file
        try? FileManager.default.removeItem(at: logURL!)
    }

    // MARK: - 5. ExpectSendEngine Rule Validation Tests

    @Test func testExpectSendEngineRuleDefinition() {
        let rule1 = ExpectSendRule(expect: "Username:", send: "admin")
        let rule2 = ExpectSendRule(expect: "Password:", send: "SecretPass123")
        let rule3 = ExpectSendRule(expect: "Router>", send: "enable")

        #expect(rule1.expect == "Username:")
        #expect(rule1.send == "admin")
        #expect(rule2.expect == "Password:")
        #expect(rule3.send == "enable")

        let engine = ExpectSendEngine.shared
        #expect(engine.isRunning == false)
    }

    // MARK: - 6. Serial Hardware Tools & Throttling Tests

    @Test func testSerialConnectionConfig() {
        let standardConfig = SerialConnectionConfig.default(for: "/dev/cu.usbserial-A101", name: "Switch Console")
        #expect(standardConfig.devicePath == "/dev/cu.usbserial-A101")
        #expect(standardConfig.baudRate == 115200)
        #expect(standardConfig.dataBits == 8)
        #expect(standardConfig.parity == "None")
        #expect(standardConfig.buildLaunchCommand() == "screen /dev/cu.usbserial-A101 115200")

        var ciscoConfig = SerialConnectionConfig.default(for: "/dev/cu.usbserial-0001", name: "Cisco Catalyst")
        ciscoConfig.baudRate = 9600
        ciscoConfig.lineDelayMs = 50
        ciscoConfig.charDelayMs = 2

        #expect(ciscoConfig.buildLaunchCommand() == "screen /dev/cu.usbserial-0001 9600")
        #expect(ciscoConfig.lineDelayMs == 50)
        #expect(ciscoConfig.charDelayMs == 2)
    }

    // MARK: - 7. High-Throughput, Concurrency & Stress Benchmark Tests

    @Test func testKeywordHighlighterStressThroughput() {
        let highlighter = KeywordHighlighter.shared
        highlighter.isEnabled = true

        // Generate 10,000 lines of simulated log stream with high frequency of IPs, errors, and statuses
        var buffer = ""
        buffer.reserveCapacity(2_000_000)
        for i in 1...10_000 {
            let status = (i % 5 == 0) ? "ERROR" : ((i % 3 == 0) ? "UP" : "OK")
            let ip = "10.\(i % 256).\(i % 128).1"
            let mac = String(format: "%02X:%02X:%02X:%02X:%02X:%02X", i % 256, (i+1)%256, (i+2)%256, 10, 20, 30)
            buffer += "Line \(i): Node \(mac) status=\(status) addr=\(ip) - Process completed\n"
        }

        let start = DispatchTime.now()
        highlighter.scan(text: buffer)
        let end = DispatchTime.now()

        let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds
        let timeIntervalMs = Double(nanoTime) / 1_000_000

        #expect(highlighter.totalMatchesCount >= 20_000)
        // High throughput requirement: scanning 10,000 lines must complete in under 500ms
        print("Stress Benchmark: Scanned 10,000 lines (\(buffer.count) chars) in \(timeIntervalMs) ms")
        #expect(timeIntervalMs < 500.0)
    }

    @Test func testSessionLoggerStressThroughput() throws {
        let logger = SessionLogger.shared
        let stressSessionName = "StressLog_\(UUID().uuidString.prefix(6))"

        logger.prependTimestamps = false // High speed pure raw write benchmark
        logger.stripANSI = true

        logger.startRecording(sessionName: stressSessionName)
        let start = DispatchTime.now()

        for i in 1...5_000 {
            logger.log(text: "\u{1B}[32m[INFO]\u{1B}[0m Packet #\(i) received from 172.16.1.\(i % 255): checksum valid\n")
        }

        let end = DispatchTime.now()
        let logURL = logger.stopRecording()

        let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds
        let timeIntervalMs = Double(nanoTime) / 1_000_000

        print("SessionLogger Benchmark: Flushed 5,000 log events in \(timeIntervalMs) ms")
        #expect(timeIntervalMs < 1000.0)
        #expect(logURL != nil)

        if let url = logURL {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = attributes[.size] as? Int64 ?? 0
            #expect(size > 100_000) // Over 100KB of cleanly written logs
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test func testConcurrentSessionContextsLoad() {
        let manager = SSHTransferManager.shared

        // Register 100 concurrent session contexts
        var uuids: [UUID] = []
        for i in 1...100 {
            let id = UUID()
            uuids.append(id)
            let s = SavedSession(
                name: "Router-\(i)",
                host: "10.10.\(i).1",
                user: "admin\(i)",
                port: 2200 + i
            )
            manager.registerContext(for: id, session: s)
        }

        // Validate all 100 contexts resolve accurately without collisions
        for (idx, id) in uuids.enumerated() {
            let i = idx + 1
            #expect(manager.hasActiveSSHContext(for: id) == true)
            let ctx = manager.context(for: id)
            #expect(ctx?.host == "10.10.\(i).1")
            #expect(ctx?.user == "admin\(i)")
            #expect(ctx?.port == 2200 + i)
        }
    }
}
