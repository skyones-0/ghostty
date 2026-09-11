import SwiftUI
import AppKit

public struct BottomTaskDrawer: View {
    @ObservedObject var taskManager = BackgroundTaskManager.shared
    var onAttachToTerminal: ((String) -> Void)? = nil

    @State private var isHovered = false

    public init(onAttachToTerminal: ((String) -> Void)? = nil) {
        self.onAttachToTerminal = onAttachToTerminal
    }

    private var selectedTask: BackgroundTaskItem? {
        if let id = taskManager.activeDrawerTaskId {
            return taskManager.tasks.first(where: { $0.id == id })
        }
        return taskManager.tasks.first
    }

    public var body: some View {
        if !taskManager.tasks.isEmpty {
            VStack(spacing: 0) {
                // Top border / divider
                Divider()

                if taskManager.isDrawerExpanded, let task = selectedTask {
                    // Expanded Console Drawer
                    VStack(spacing: 0) {
                        // Header Bar
                        HStack(spacing: 8) {
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
                            .font(.system(size: 11))

                            // Task Selector Menu if multiple tasks
                            if taskManager.tasks.count > 1 {
                                Menu {
                                    ForEach(taskManager.tasks) { t in
                                        Button {
                                            taskManager.activeDrawerTaskId = t.id
                                        } label: {
                                            HStack {
                                                Text(t.title)
                                                Spacer()
                                                Text(t.durationString)
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(task.title)
                                            .font(.system(size: 11, weight: .semibold))
                                            .lineLimit(1)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            } else {
                                Text(task.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                            }

                            // Elapsed time
                            Text(task.durationString)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Spacer()

                            // Action: Stop if running
                            if !task.status.isTerminal {
                                Button {
                                    taskManager.stop(id: task.id)
                                } label: {
                                    Label("Stop", systemImage: "stop.fill")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .focusable(false)
                            }

                            // Action: Copy Output
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(task.output, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Copy logs to clipboard")
                            .focusable(false)

                            // Action: Clear finished
                            Button {
                                taskManager.clearFinished()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Clear finished tasks")
                            .focusable(false)

                            // Minimize drawer
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    taskManager.isDrawerExpanded = false
                                }
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .windowBackgroundColor))

                        Divider()

                        // Console Log Area
                        ScrollViewReader { scrollProxy in
                            ScrollView(.vertical) {
                                Text(task.output)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color(nsColor: .textColor))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .padding(8)
                                    .id("logBottom")
                            }
                            .background(Color.black.opacity(0.85))
                            .frame(height: 130)
                            .onChange(of: task.output) { _ in
                                scrollProxy.scrollTo("logBottom", anchor: .bottom)
                            }
                        }
                    }
                } else {
                    // Collapsed Status Pill Bar
                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            if taskManager.activeCount > 0 {
                                ProgressView()
                                    .controlSize(.mini)
                                    .frame(width: 10, height: 10)
                                Text("\(taskManager.activeCount) task\(taskManager.activeCount == 1 ? "" : "s") running")
                                    .font(.system(size: 11, weight: .medium))
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.green)
                                Text("Tasks completed")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let first = taskManager.tasks.first {
                            Text("• \(first.title)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Text(first.durationString)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary.opacity(0.8))
                        }

                        Spacer()

                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                taskManager.isDrawerExpanded = true
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text("Logs")
                                    .font(.system(size: 10, weight: .semibold))
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)

                        Button {
                            taskManager.clearFinished()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            taskManager.isDrawerExpanded = true
                        }
                    }
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
