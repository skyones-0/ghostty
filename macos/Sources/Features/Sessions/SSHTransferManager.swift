import SwiftUI
import AppKit

public struct FileTransferProgress: Identifiable, Equatable {
    public var id = UUID()
    public var fileName: String
    public var isUpload: Bool
    public var percentage: Double // 0.0 ... 1.0
    public var detailText: String
}

public struct CompletedTransferToast: Identifiable, Equatable {
    public var id = UUID()
    public var fileName: String
    public var isUpload: Bool
    public var localURL: URL
    public var remotePath: String
}

public struct ActiveSSHContext: Equatable {
    public var host: String
    public var user: String?
    public var port: Int?
    public var identityFile: String?
    public var jumpHost: String?
    public var controlPath: String

    public init(
        host: String,
        user: String? = nil,
        port: Int? = 22,
        identityFile: String? = nil,
        jumpHost: String? = nil
    ) {
        self.host = host
        self.user = user
        self.port = port
        self.identityFile = identityFile
        self.jumpHost = jumpHost
        self.controlPath = "/tmp/spectre-ssh-%C.sock"
    }

    public var targetSpec: String {
        if let u = user, !u.isEmpty {
            return "\(u)@\(host)"
        }
        return host
    }

    public func buildBaseSCPArguments() -> [String] {
        var args = [
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(controlPath)",
            "-o", "ControlPersist=10m"
        ]

        if let p = port, p != 22 {
            args += ["-P", "\(p)"]
        }
        if let key = identityFile, !key.isEmpty {
            let expanded = (key as NSString).expandingTildeInPath
            args += ["-i", expanded]
        }
        if let jump = jumpHost, !jump.isEmpty {
            args += ["-J", jump]
        }
        return args
    }
}

@MainActor
public final class SSHTransferManager: ObservableObject {
    public static let shared = SSHTransferManager()

    @Published public var activeTransfer: FileTransferProgress? = nil
    @Published public var completedToast: CompletedTransferToast? = nil

    // Active session contexts mapped by surface UUID
    private var contexts: [UUID: ActiveSSHContext] = [:]
    private var currentProcess: Process? = nil

    private init() {}

    public func registerContext(for surfaceId: UUID, session: SavedSession) {
        let ctx = ActiveSSHContext(
            host: session.host,
            user: session.user,
            port: session.port,
            identityFile: session.identityFile,
            jumpHost: session.jumpHost
        )
        contexts[surfaceId] = ctx
    }

    public func hasActiveSSHContext(for surfaceId: UUID) -> Bool {
        return contexts[surfaceId] != nil
    }

    public func context(for surfaceId: UUID) -> ActiveSSHContext? {
        return contexts[surfaceId]
    }

    // MARK: - Upload

    func uploadFiles(_ urls: [URL], surface: Ghostty.SurfaceView) {
        guard let ctx = contexts[surface.id] else {
            // Fallback: If no explicit SavedSession context, just type the local paths
            let paths = urls.map { $0.path }.joined(separator: " ")
            surface.surfaceModel?.sendText(paths)
            return
        }

        let validFiles = urls.filter { $0.isFileURL }
        guard !validFiles.isEmpty else { return }

        Task {
            for fileURL in validFiles {
                await performUpload(fileURL: fileURL, context: ctx, surface: surface)
            }
        }
    }

    private func performUpload(fileURL: URL, context: ActiveSSHContext, surface: Ghostty.SurfaceView) async {
        let fileName = fileURL.lastPathComponent
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        let formattedSize = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)

        await MainActor.run {
            self.activeTransfer = FileTransferProgress(
                fileName: fileName,
                isUpload: true,
                percentage: 0.1,
                detailText: "Uploading \(fileName) (\(formattedSize))..."
            )
        }

        var scpArgs = context.buildBaseSCPArguments()
        scpArgs.append(fileURL.path)
        scpArgs.append("\(context.targetSpec):./")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        process.arguments = scpArgs

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        self.currentProcess = process

        do {
            try process.run()

            // Animate progress smoothly while running
            for p in stride(from: 0.2, through: 0.9, by: 0.1) {
                try? await Task.sleep(nanoseconds: 150_000_000)
                if !process.isRunning { break }
                await MainActor.run {
                    if var current = self.activeTransfer {
                        current.percentage = p
                        self.activeTransfer = current
                    }
                }
            }

            process.waitUntilExit()

            let success = process.terminationStatus == 0

            await MainActor.run {
                self.activeTransfer = nil
                self.currentProcess = nil

                if success {
                    // Type the remote path in terminal prompt
                    surface.surfaceModel?.sendText("./\(fileName) ")

                    self.completedToast = CompletedTransferToast(
                        fileName: fileName,
                        isUpload: true,
                        localURL: fileURL,
                        remotePath: "./\(fileName)"
                    )

                    // Auto dismiss toast after 4 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                        if self.completedToast?.fileName == fileName {
                            self.completedToast = nil
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.activeTransfer = nil
                self.currentProcess = nil
            }
        }
    }

    // MARK: - Download

    func downloadFile(remotePath: String, surface: Ghostty.SurfaceView) {
        guard let ctx = contexts[surface.id] else { return }

        let trimmedPath = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }

        let fileName = (trimmedPath as NSString).lastPathComponent
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let localDestURL = downloadsURL.appendingPathComponent(fileName)

        Task {
            await performDownload(remotePath: trimmedPath, fileName: fileName, localDestURL: localDestURL, context: ctx)
        }
    }

    private func performDownload(remotePath: String, fileName: String, localDestURL: URL, context: ActiveSSHContext) async {
        await MainActor.run {
            self.activeTransfer = FileTransferProgress(
                fileName: fileName,
                isUpload: false,
                percentage: 0.1,
                detailText: "Downloading \(fileName)..."
            )
        }

        var scpArgs = context.buildBaseSCPArguments()
        scpArgs.append("\(context.targetSpec):\(remotePath)")
        scpArgs.append(localDestURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        process.arguments = scpArgs

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        self.currentProcess = process

        do {
            try process.run()

            for p in stride(from: 0.2, through: 0.9, by: 0.1) {
                try? await Task.sleep(nanoseconds: 150_000_000)
                if !process.isRunning { break }
                await MainActor.run {
                    if var current = self.activeTransfer {
                        current.percentage = p
                        self.activeTransfer = current
                    }
                }
            }

            process.waitUntilExit()

            let success = process.terminationStatus == 0

            await MainActor.run {
                self.activeTransfer = nil
                self.currentProcess = nil

                if success {
                    self.completedToast = CompletedTransferToast(
                        fileName: fileName,
                        isUpload: false,
                        localURL: localDestURL,
                        remotePath: remotePath
                    )

                    // Auto dismiss toast after 6 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                        if self.completedToast?.fileName == fileName {
                            self.completedToast = nil
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.activeTransfer = nil
                self.currentProcess = nil
            }
        }
    }

    public func cancelActiveTransfer() {
        currentProcess?.terminate()
        currentProcess = nil
        activeTransfer = nil
    }

    public func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func openFile(url: URL) {
        NSWorkspace.shared.open(url)
    }
}
