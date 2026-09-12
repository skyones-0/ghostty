import Foundation
import Cocoa
import Testing
@testable import Ghostty

@MainActor
struct SpectreProQATests {

    // MARK: - 1. Quick Terminal Architecture & Multi-Space Capabilities

    @Test func testQuickTerminalSpaceBehaviorMove() {
        let behavior = QuickTerminalSpaceBehavior(fromGhosttyConfig: "move")
        #expect(behavior == .move)

        let collectionBehavior = behavior!.collectionBehavior
        #expect(collectionBehavior.contains(.canJoinAllSpaces))
        #expect(collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(collectionBehavior.contains(.ignoresCycle))
    }

    @Test func testQuickTerminalSpaceBehaviorRemain() {
        let behavior = QuickTerminalSpaceBehavior(fromGhosttyConfig: "remain")
        #expect(behavior == .remain)

        let collectionBehavior = behavior!.collectionBehavior
        #expect(collectionBehavior.contains(.moveToActiveSpace))
        #expect(collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(collectionBehavior.contains(.ignoresCycle))
    }

    @Test func testQuickTerminalScreenOptions() {
        let main = QuickTerminalScreen(fromGhosttyConfig: "main")
        #expect(main == .main)
        #expect(main?.screen != nil)

        let mouse = QuickTerminalScreen(fromGhosttyConfig: "mouse")
        #expect(mouse == .mouse)
        #expect(mouse?.screen != nil)

        let menuBar = QuickTerminalScreen(fromGhosttyConfig: "macos-menu-bar")
        #expect(menuBar == .menuBar)
        #expect(menuBar?.screen != nil)

        let invalid = QuickTerminalScreen(fromGhosttyConfig: "nonexistent")
        #expect(invalid == nil)
    }

    @Test func testQuickTerminalPositions() {
        let top = QuickTerminalPosition.top
        let bottom = QuickTerminalPosition.bottom
        let left = QuickTerminalPosition.left
        let right = QuickTerminalPosition.right
        let center = QuickTerminalPosition.center

        #expect(top != bottom)
        #expect(left != right)
        #expect(center != top)
    }

    // MARK: - 2. Rebranding & Asset Integrity Tests

    @Test func testRebrandedAssetsExistence() {
        let fm = FileManager.default

        // Verify root Spectre.icns exists and has content
        let icnsURL = URL(fileURLWithPath: "/Users/jaraujo/Developer/ghostty/images/Spectre.icns")
        #expect(fm.fileExists(atPath: icnsURL.path))

        if let attrs = try? fm.attributesOfItem(atPath: icnsURL.path),
           let size = attrs[.size] as? Int64 {
            // Must be a fully-formed multi-resolution ICNS (> 50KB)
            #expect(size > 50_000)
        }

        // Verify AppIconImage assets exist in Assets.xcassets
        let appIconDir = "/Users/jaraujo/Developer/ghostty/macos/Assets.xcassets/AppIconImage.imageset"
        #expect(fm.fileExists(atPath: "\(appIconDir)/macOS-AppIcon-1024px.png"))
        #expect(fm.fileExists(atPath: "\(appIconDir)/macOS-AppIcon-512px.png"))
        #expect(fm.fileExists(atPath: "\(appIconDir)/macOS-AppIcon-256px-128pt@2x.png"))
    }

    @Test func testAlternateIconsAllRebranded() {
        let fm = FileManager.default
        let baseDir = "/Users/jaraujo/Developer/ghostty/macos/Assets.xcassets/Alternate Icons"
        let variants = [
            "BlueprintImage.imageset",
            "ChalkboardImage.imageset",
            "GlassImage.imageset",
            "HolographicImage.imageset",
            "MicrochipImage.imageset",
            "PaperImage.imageset",
            "RetroImage.imageset",
            "XrayImage.imageset"
        ]

        for variant in variants {
            let path = "\(baseDir)/\(variant)/macOS-AppIcon-1024px.png"
            #expect(fm.fileExists(atPath: path))
            if let attrs = try? fm.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                #expect(size > 10_000)
            }
        }
    }

    // MARK: - 3. High-Stress & Performance Benchmarks

    @Test func testQuickTerminalPositioningStress() {
        let start = DispatchTime.now()
        let screens = NSScreen.screens
        guard let testScreen = screens.first else { return }

        var dummyWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        let size = QuickTerminalSize()
        let closedFrame = NSRect(x: 0, y: 0, width: 800, height: 600)

        // Run 1,000 rapid layout computations across all positions
        for _ in 1...1_000 {
            QuickTerminalPosition.top.setInitial(
                in: dummyWindow,
                on: testScreen,
                terminalSize: size,
                closedFrame: closedFrame
            )
            QuickTerminalPosition.top.setFinal(
                in: dummyWindow,
                on: testScreen,
                terminalSize: size,
                closedFrame: closedFrame
            )
        }

        let end = DispatchTime.now()
        let elapsedMs = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0

        print("Quick Terminal Layout Stress: 2,000 operations completed in \(elapsedMs) ms")
        // Must complete 2,000 operations in under 500ms
        #expect(elapsedMs < 500.0)
    }

    @Test func testBulkSessionPoolStress() throws {
        let start = DispatchTime.now()
        var sessions: [SavedSession] = []
        sessions.reserveCapacity(1_000)

        // 1. Generate 1,000 enterprise sessions
        for i in 1...1_000 {
            let s = SavedSession(
                name: "Cluster-Node-\(i)",
                folder: "Production/DC-\(i % 10)",
                host: "node\(i).compute.internal",
                user: "ops-engineer",
                port: 2200 + (i % 50),
                environmentBadge: (i % 3 == 0) ? "PROD" : "STAGING",
                portForwards: [
                    PortForwardRule(type: .local, localPort: 8000 + i, remoteHost: "127.0.0.1", remotePort: 80)
                ]
            )
            sessions.append(s)
        }

        // 2. Stress JSON Serialization
        let encoder = JSONEncoder()
        let data = try encoder.encode(sessions)
        #expect(data.count > 100_000)

        // 3. Stress JSON Deserialization
        let decoder = JSONDecoder()
        let decoded = try decoder.decode([SavedSession].self, from: data)
        #expect(decoded.count == 1_000)
        #expect(decoded[500].name == "Cluster-Node-501")

        let end = DispatchTime.now()
        let elapsedMs = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0

        print("Session Pool Stress: Encoded and decoded 1,000 sessions in \(elapsedMs) ms")
        // Benchmark requirement: must finish under 200ms
        #expect(elapsedMs < 200.0)
    }

    @Test func testHighVolumeANSIScannerStress() {
        let highlighter = KeywordHighlighter.shared
        highlighter.isEnabled = true

        // Generate 25,000 lines of high-volume ANSI log flood
        var stream = ""
        stream.reserveCapacity(5_000_000)

        for i in 1...25_000 {
            let status = (i % 4 == 0) ? "CRITICAL" : ((i % 2 == 0) ? "ERROR" : "ESTABLISHED")
            let ip = "192.168.\(i % 255).\( (i * 3) % 255)"
            stream += "[SYS] Event #\(i): Node status=\(status) ip=\(ip) line=UP\n"
        }

        let start = DispatchTime.now()
        highlighter.scan(text: stream)
        let end = DispatchTime.now()

        let elapsedMs = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
        print("High Volume Scanner Stress: Processed 25,000 log lines (\(stream.count) chars) in \(elapsedMs) ms")

        #expect(highlighter.totalMatchesCount >= 50_000)
        // High throughput requirement: must scan 25,000 lines in under 800ms
        #expect(elapsedMs < 800.0)
    }
}
