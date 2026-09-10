import Foundation
import Combine
import Darwin

enum TerminalJobState: String, Sendable, Equatable {
    case running
    case waiting
    case stopped
}

struct TerminalJob: Identifiable, Equatable {
    var id: Int32 { pid }
    let pid: Int32
    let name: String
    let commandLine: String?
    let pgid: Int32
    let isForeground: Bool
    var state: TerminalJobState = .running
    var isActive: Bool = true

    var isWaiting: Bool {
        state == .waiting
    }

    var activityStatusText: String {
        isActive ? "active" : "idle"
    }
}

@MainActor
final class TerminalProcessMonitor: ObservableObject {
    @Published private(set) var runningJobs: [TerminalJob] = []
    @Published private(set) var recentExits: [String] = []
    @Published private(set) var currentWorkingDir: String?
    @Published private(set) var activePortAlert: LocalPortInfo?

    var foregroundJob: TerminalJob? {
        runningJobs.first(where: { $0.isForeground })
    }

    var backgroundJobs: [TerminalJob] {
        runningJobs.filter { !$0.isForeground }
    }

    private func getCwd(pid: pid_t) -> String? {
        var vpi = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.size
        let res = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vpi, Int32(size))
        guard res == size else { return nil }
        return withUnsafePointer(to: vpi.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                let str = String(cString: $0)
                return str.isEmpty ? nil : str
            }
        }
    }

    private func getCommandLine(pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        var argc: Int32 = 0
        memcpy(&argc, buffer, MemoryLayout<Int32>.size)
        guard argc > 0 else { return nil }

        var idx = MemoryLayout<Int32>.size
        while idx < size && buffer[idx] != 0 { idx += 1 }
        while idx < size && buffer[idx] == 0 { idx += 1 }

        var args: [String] = []
        while idx < size && args.count < argc {
            let start = idx
            while idx < size && buffer[idx] != 0 { idx += 1 }
            if idx > start {
                let arg = buffer[start..<idx].withUnsafeBufferPointer { ptr in
                    String(cString: ptr.baseAddress!)
                }
                args.append(arg)
            }
            idx += 1
        }
        return args.isEmpty ? nil : args.joined(separator: " ")
    }

    private func getCpuTime(pid: pid_t) -> UInt64 {
        var ti = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size
        let res = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, Int32(size))
        guard res == size else { return 0 }
        return ti.pti_total_user + ti.pti_total_system
    }

    let portDetector = LocalPortDetector()
    var isFocused: Bool = true
    private var previousForegroundPid: Int32?

    private var timer: Timer?
    private weak var surfaceView: Ghostty.SurfaceView?
    private var previousPids: Set<Int32> = []
    private var knownNames: [Int32: String] = [:]
    private var previousCpuTimes: [Int32: UInt64] = [:]
    private var lastActiveTimes: [Int32: Date] = [:]

    init(surfaceView: Ghostty.SurfaceView? = nil) {
        self.surfaceView = surfaceView
        startMonitoring()
    }

    deinit {
        timer?.invalidate()
    }

    func setSurfaceView(_ view: Ghostty.SurfaceView?) {
        guard self.surfaceView !== view else { return }
        self.surfaceView = view
        previousPids.removeAll()
        knownNames.removeAll()
        previousCpuTimes.removeAll()
        lastActiveTimes.removeAll()
        refresh()
    }

    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        refresh()
    }

    func terminateJob(_ job: TerminalJob) {
        kill(job.pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            if kill(job.pid, 0) == 0 {
                kill(job.pid, SIGKILL)
            }
            self?.refresh()
        }
        refresh()
    }

    func dismissPortAlert() {
        portDetector.dismissAlert()
        activePortAlert = nil
    }

    func refresh() {
        guard let model = surfaceView?.surfaceModel,
              let ttyName = model.ttyName,
              !ttyName.isEmpty else {
            if !runningJobs.isEmpty { runningJobs = [] }
            return
        }

        let foregroundPID = Int32(model.foregroundPID ?? 0)

        var statBuf = stat()
        guard stat(ttyName, &statBuf) == 0 else { return }
        let dev = statBuf.st_rdev

        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_TTY, Int32(dev)]
        var size: Int = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return }

        let ignoredNames: Set<String> = ["zsh", "bash", "fish", "sh", "login", "ghostty"]

        var currentJobs: [TerminalJob] = []
        var currentPids = Set<Int32>()

        for p in procs {
            let pid = p.kp_proc.p_pid
            guard pid > 0 else { continue }
            let name = withUnsafePointer(to: p.kp_proc.p_comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN + 1)) {
                    String(cString: $0)
                }
            }
            if ignoredNames.contains(name.lowercased()) { continue }

            let pgid = p.kp_eproc.e_pgid
            let isFg = (foregroundPID != 0 && (pid == foregroundPID || pgid == foregroundPID))
            let cmdLine = getCommandLine(pid: pid)

            let stat = Int32(p.kp_proc.p_stat)
            let jobState: TerminalJobState
            switch stat {
            case SSLEEP:
                jobState = .waiting
            case SSTOP:
                jobState = .stopped
            default:
                jobState = .running
            }

            let cpuTime = getCpuTime(pid: pid)
            let prevCpu = previousCpuTimes[pid] ?? cpuTime
            let deltaCpu = (cpuTime >= prevCpu) ? (cpuTime - prevCpu) : 0
            previousCpuTimes[pid] = cpuTime

            // Check if process has child processes (e.g. tools executed by the process)
            let hasChildProcesses = procs.contains { $0.kp_eproc.e_ppid == pid }

            // Process is actively computing if delta CPU > 2ms or has child processes
            let isActivelyComputing = (deltaCpu > 2_000) || hasChildProcesses

            if isActivelyComputing {
                lastActiveTimes[pid] = Date()
            }

            // A monitored process is active if it computed recently (within 2.5s grace period)
            let active: Bool
            if let lastActive = lastActiveTimes[pid] {
                active = Date().timeIntervalSince(lastActive) < 2.5
            } else {
                active = isActivelyComputing
            }

            let job = TerminalJob(
                pid: pid,
                name: name,
                commandLine: cmdLine,
                pgid: pgid,
                isForeground: isFg,
                state: jobState,
                isActive: active
            )
            currentJobs.append(job)
            currentPids.insert(pid)
            knownNames[pid] = name
        }

        // Detect exited processes
        let exitedPids = previousPids.subtracting(currentPids)
        for exited in exitedPids {
            previousCpuTimes.removeValue(forKey: exited)
            lastActiveTimes.removeValue(forKey: exited)
            if let name = knownNames[exited] {
                showExit(name)
                knownNames.removeValue(forKey: exited)
            }
        }

        previousPids = currentPids
        runningJobs = currentJobs

        // Inspect local listening ports on processes attached to this session
        let allSessionPids = procs.map { $0.kp_proc.p_pid }.filter { $0 > 0 }
        portDetector.inspect(pids: allSessionPids, names: knownNames)
        self.activePortAlert = portDetector.activeAlert

        // Track foreground command execution for long-running notifications
        if let fg = currentJobs.first(where: { $0.isForeground }) {
            if fg.pid != previousForegroundPid {
                if let surfaceId = surfaceView?.id {
                    LongCommandNotifier.shared.commandDidStart(name: fg.name, commandLine: fg.commandLine, surfaceUUID: surfaceId)
                }
                previousForegroundPid = fg.pid
            }
        } else {
            if previousForegroundPid != nil {
                if let surfaceId = surfaceView?.id {
                    LongCommandNotifier.shared.commandDidFinish(surfaceUUID: surfaceId, isFocused: isFocused)
                }
                previousForegroundPid = nil
            }
        }

        // Query Current Working Directory
        var targetPidForCwd: pid_t = 0
        if foregroundPID > 0 {
            targetPidForCwd = pid_t(foregroundPID)
        } else {
            for p in procs {
                let name = withUnsafePointer(to: p.kp_proc.p_comm) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN + 1)) {
                        String(cString: $0)
                    }
                }
                if name == "zsh" || name == "bash" || name == "fish" || name == "sh" {
                    targetPidForCwd = p.kp_proc.p_pid
                    break
                }
            }
        }
        if targetPidForCwd > 0, let cwd = getCwd(pid: targetPidForCwd), !cwd.isEmpty {
            currentWorkingDir = cwd
        }
    }

    private func showExit(_ name: String) {
        recentExits.append(name)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if let idx = self.recentExits.firstIndex(of: name) {
                self.recentExits.remove(at: idx)
            }
        }
    }
}
