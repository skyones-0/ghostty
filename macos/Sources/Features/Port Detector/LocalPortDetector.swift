import Foundation
import Combine
import Darwin
import CoreFoundation

/// Represents a listening local server port.
struct LocalPortInfo: Identifiable, Equatable, Hashable {
    var id: Int { port }
    let port: Int
    let processName: String
    let pid: pid_t
    let detectedAt: Date

    var url: URL {
        URL(string: "http://localhost:\(port)")!
    }
}

/// Detects local network ports listening on TCP via native Darwin proc_pidinfo APIs.
/// Zero overhead: runs on-demand during process monitor updates.
@MainActor
final class LocalPortDetector: ObservableObject {
    @Published var activeAlert: LocalPortInfo?
    @Published private(set) var openPorts: [LocalPortInfo] = []

    private var notifiedPorts: Set<Int> = []
    private var autoDismissTask: Task<Void, Never>?

    private static let PROC_PIDLISTFDS: Int32 = 1
    private static let PROC_PIDFDSOCKETINFO: Int32 = 3
    private static let PROX_FDTYPE_SOCKET: UInt32 = 2
    private static let SOCKINFO_TCP: Int32 = 2
    private static let TSI_S_LISTEN: Int32 = 1

    /// Inspect a list of process jobs belonging to the terminal session.
    func inspect(pids: [pid_t], names: [pid_t: String]) {
        var currentPorts: [LocalPortInfo] = []

        for pid in pids {
            let procPorts = getListeningPorts(for: pid)
            guard !procPorts.isEmpty else { continue }

            var name = names[pid]
            if name == nil || name?.isEmpty == true {
                var nameBuffer = [CChar](repeating: 0, count: 256)
                proc_name(pid, &nameBuffer, 256)
                let resolved = String(cString: nameBuffer)
                name = resolved.isEmpty ? "process" : resolved
            }
            let displayName = name ?? "process"

            for port in procPorts {
                // Filter out standard non-dev internal ports or privileged ports below 80
                guard port >= 80 && port <= 65535 else { continue }
                // Avoid notifying common system ports
                if port == 5000 && displayName.lowercased().contains("controlcenter") { continue }

                let info = LocalPortInfo(
                    port: port,
                    processName: displayName,
                    pid: pid,
                    detectedAt: Date()
                )
                currentPorts.append(info)

                if !notifiedPorts.contains(port) {
                    notifiedPorts.insert(port)
                    triggerAlert(for: info)
                }
            }
        }

        // Clean up notified ports that have closed
        let activePortNumbers = Set(currentPorts.map { $0.port })
        notifiedPorts = notifiedPorts.intersection(activePortNumbers)

        // Dismiss alert if the port closed
        if let currentAlert = activeAlert, !activePortNumbers.contains(currentAlert.port) {
            dismissAlert()
        }

        self.openPorts = currentPorts
    }

    private func getListeningPorts(for pid: pid_t) -> [Int] {
        let bufSize = proc_pidinfo(pid, Self.PROC_PIDLISTFDS, 0, nil, 0)
        guard bufSize > 0 else { return [] }

        let count = Int(bufSize) / MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: count)
        let actualSize = proc_pidinfo(pid, Self.PROC_PIDLISTFDS, 0, &fds, bufSize)
        guard actualSize > 0 else { return [] }

        let actualCount = Int(actualSize) / MemoryLayout<proc_fdinfo>.stride
        var result: [Int] = []
        for i in 0..<actualCount {
            let fd = fds[i]
            guard fd.proc_fdtype == Self.PROX_FDTYPE_SOCKET else { continue }

            var sockInfo = socket_fdinfo()
            let sockSize = Int32(MemoryLayout<socket_fdinfo>.size)
            let r = proc_pidfdinfo(pid, fd.proc_fd, Self.PROC_PIDFDSOCKETINFO, &sockInfo, sockSize)
            guard r == sockSize else { continue }

            let sock = sockInfo.psi
            if sock.soi_kind == Self.SOCKINFO_TCP {
                let tcp = sock.soi_proto.pri_tcp
                if tcp.tcpsi_state == Self.TSI_S_LISTEN {
                    let rawPort = tcp.tcpsi_ini.insi_lport
                    let port = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: rawPort)))
                    if port > 0 && !result.contains(port) {
                        result.append(port)
                    }
                }
            }
        }
        return result
    }

    private func triggerAlert(for portInfo: LocalPortInfo) {
        activeAlert = portInfo
        autoDismissTask?.cancel()
        autoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard let self = self else { return }
            if self.activeAlert == portInfo {
                self.dismissAlert()
            }
        }
    }

    func dismissAlert() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        activeAlert = nil
    }
}
