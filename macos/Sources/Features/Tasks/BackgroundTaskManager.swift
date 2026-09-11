import Foundation
import Combine

public enum BackgroundTaskStatus: Equatable {
    case running
    case succeeded
    case failed(Int32)
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .running: return false
        case .succeeded, .failed, .cancelled: return true
        }
    }

    public var displayText: String {
        switch self {
        case .running: return "Running"
        case .succeeded: return "Done"
        case .failed(let code): return "Failed (\(code))"
        case .cancelled: return "Stopped"
        }
    }
}

public struct BackgroundTaskItem: Identifiable {
    public let id: UUID
    public let title: String
    public let command: String
    public var status: BackgroundTaskStatus
    public let startedAt: Date
    public var finishedAt: Date?
    public var output: String
    public var pid: Int32?
    public let workingDirectory: String?

    public var durationString: String {
        let end = finishedAt ?? Date()
        let interval = max(0, Int(end.timeIntervalSince(startedAt)))
        let minutes = interval / 60
        let seconds = interval % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

@MainActor
public final class BackgroundTaskManager: ObservableObject {
    public static let shared = BackgroundTaskManager()

    @Published public private(set) var tasks: [BackgroundTaskItem] = []
    @Published public var activeDrawerTaskId: UUID? = nil
    @Published public var isDrawerExpanded: Bool = false

    private var runningProcesses: [UUID: Process] = [:]
    private var taskPipes: [UUID: Pipe] = [:]
    private let maxOutputLength = 100_000

    public var activeTasks: [BackgroundTaskItem] {
        tasks.filter { !$0.status.isTerminal }
    }

    public var activeCount: Int {
        activeTasks.count
    }

    private init() {}

    @discardableResult
    public func run(command: String, title: String? = nil, workingDirectory: String? = nil) -> UUID {
        let taskId = UUID()
        let displayTitle = title?.trimmingCharacters(in: .whitespaces).isEmpty == false
            ? title!
            : (command.components(separatedBy: "\n").first ?? command)

        let taskItem = BackgroundTaskItem(
            id: taskId,
            title: displayTitle,
            command: command,
            status: .running,
            startedAt: Date(),
            finishedAt: nil,
            output: "$ \(command)\n",
            pid: nil,
            workingDirectory: workingDirectory
        )

        tasks.insert(taskItem, at: 0)
        activeDrawerTaskId = taskId
        isDrawerExpanded = true

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]

        if let wd = workingDirectory, FileManager.default.fileExists(atPath: wd) {
            process.currentDirectoryURL = URL(fileURLWithPath: wd)
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        runningProcesses[taskId] = process
        taskPipes[taskId] = pipe

        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else { return }
            Task { @MainActor in
                self?.appendOutput(to: taskId, text: text)
            }
        }

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.handleTermination(for: taskId, exitCode: proc.terminationStatus)
            }
        }

        do {
            try process.run()
            if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
                tasks[idx].pid = process.processIdentifier
            }
        } catch {
            appendOutput(to: taskId, text: "\n[Error launching task: \(error.localizedDescription)]\n")
            handleTermination(for: taskId, exitCode: -1)
        }

        return taskId
    }

    public func stop(id: UUID) {
        guard let process = runningProcesses[id], process.isRunning else { return }
        process.terminate()
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            tasks[idx].status = .cancelled
            tasks[idx].finishedAt = Date()
        }
        cleanup(id: id)
    }

    public func clearFinished() {
        tasks.removeAll { $0.status.isTerminal }
        if let activeId = activeDrawerTaskId, !tasks.contains(where: { $0.id == activeId }) {
            activeDrawerTaskId = tasks.first?.id
            if activeDrawerTaskId == nil {
                isDrawerExpanded = false
            }
        }
    }

    public func remove(id: UUID) {
        stop(id: id)
        tasks.removeAll { $0.id == id }
        if activeDrawerTaskId == id {
            activeDrawerTaskId = tasks.first?.id
            if activeDrawerTaskId == nil {
                isDrawerExpanded = false
            }
        }
    }

    private func appendOutput(to taskId: UUID, text: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        var current = tasks[idx].output + text
        if current.count > maxOutputLength {
            let overflow = current.count - maxOutputLength
            current = String(current.dropFirst(overflow))
        }
        tasks[idx].output = current
    }

    private func handleTermination(for taskId: UUID, exitCode: Int32) {
        if let pipe = taskPipes[taskId] {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
            if tasks[idx].status == .running {
                tasks[idx].status = exitCode == 0 ? .succeeded : .failed(exitCode)
                tasks[idx].finishedAt = Date()
            }
        }
        cleanup(id: taskId)
    }

    private func cleanup(id: UUID) {
        runningProcesses.removeValue(forKey: id)
        taskPipes.removeValue(forKey: id)
    }
}
