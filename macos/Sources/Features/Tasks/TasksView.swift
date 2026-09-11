import SwiftUI
import AppKit

public struct TasksView: View {
    @ObservedObject var taskManager = BackgroundTaskManager.shared
    var onAttachToTerminal: ((String) -> Void)? = nil

    @State private var selectedTaskId: UUID? = nil
    @State private var isCreatingTask = false
    @State private var newCommandText = ""
    @State private var newCommandTitle = ""
    @State private var searchText = ""

    public init(onAttachToTerminal: ((String) -> Void)? = nil) {
        self.onAttachToTerminal = onAttachToTerminal
    }

    private var filteredTasks: [BackgroundTaskItem] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return taskManager.tasks
        }
        let q = searchText.lowercased()
        return taskManager.tasks.filter {
            $0.title.lowercased().contains(q) || $0.command.lowercased().contains(q)
        }
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                SidebarSectionPicker()

                Spacer()

                Button {
                    isCreatingTask = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Launch New Background Task")
                .focusable(false)

                if !taskManager.tasks.isEmpty {
                    Button {
                        taskManager.clearFinished()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear Finished Tasks")
                    .focusable(false)
                }
            }

            // Search
            if !taskManager.tasks.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Filter tasks...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
            }

            if taskManager.tasks.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text("No Background Tasks")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Text("Execute long-running builds, servers, or scripts in the background without blocking your terminal.")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                    Button("Run Command in Background") {
                        isCreatingTask = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .focusable(false)
                    Spacer()
                }
            } else {
                // List of tasks
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredTasks) { task in
                            TaskRowCard(
                                task: task,
                                isSelected: selectedTaskId == task.id,
                                onSelect: {
                                    if selectedTaskId == task.id {
                                        selectedTaskId = nil
                                    } else {
                                        selectedTaskId = task.id
                                    }
                                },
                                onStop: { taskManager.stop(id: task.id) },
                                onDelete: { taskManager.remove(id: task.id) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $isCreatingTask) {
            NewTaskModal(
                onRun: { title, cmd in
                    taskManager.run(command: cmd, title: title)
                }
            )
        }
    }
}

private struct TaskRowCard: View {
    let task: BackgroundTaskItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onStop: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // Status icon
                Group {
                    switch task.status {
                    case .running:
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 12, height: 12)
                    case .succeeded:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failed:
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    case .cancelled:
                        Image(systemName: "stop.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 12))

                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)

                    Text(task.command)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(task.durationString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)

                // Menu button
                Menu {
                    if !task.status.isTerminal {
                        Button("Stop Task", systemImage: "stop.fill") { onStop() }
                    }
                    Button("Copy Logs", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(task.output, forType: .string)
                    }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .focusable(false)
            }

            // Expanded log peek
            if isSelected {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    HStack {
                        Text("PID: \(task.pid.map { String($0) } ?? "–")")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(task.output, forType: .string)
                        }
                        .font(.system(size: 9))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }

                    ScrollView(.vertical) {
                        Text(task.output)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color(nsColor: .textColor))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                    }
                    .frame(maxHeight: 120)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(4)
                }
                .padding(.top, 2)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.primary.opacity(0.08) : (isHovered ? Color.primary.opacity(0.04) : Color(nsColor: .controlBackgroundColor)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
    }
}

private struct NewTaskModal: View {
    let onRun: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var command: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Launch Background Task")
                .font(.headline)

            Text("The command runs in a background zsh subshell with live output capture.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Task Name (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Build Project or Ping Host", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Command")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $command)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .focusable(false)
                Button("Run in Background") {
                    let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        onRun(title, trimmed)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .focusable(false)
            }
        }
        .padding(18)
        .frame(width: 380)
    }
}
