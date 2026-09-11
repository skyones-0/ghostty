import SwiftUI
import GhosttyKit

public struct SidebarHubView: View {
    let configuredCommands: [QuickCommand]
    let surface: Ghostty.SurfaceView?
    let send: (QuickCommand, String?, Bool, Bool) -> Void
    var splitAndSend: ((QuickCommand, String?, Bool) -> Void)?
    var onPerformAction: ((String) -> Void)? = nil

    @ObservedObject private var state = QuickCommandsState.shared
    @ObservedObject private var serialWatcher = SerialDeviceWatcher.shared
    @ObservedObject private var taskManager = BackgroundTaskManager.shared

    init(
        configuredCommands: [QuickCommand],
        surface: Ghostty.SurfaceView?,
        send: @escaping (QuickCommand, String?, Bool, Bool) -> Void,
        splitAndSend: ((QuickCommand, String?, Bool) -> Void)? = nil,
        onPerformAction: ((String) -> Void)? = nil
    ) {
        self.configuredCommands = configuredCommands
        self.surface = surface
        self.send = send
        self.splitAndSend = splitAndSend
        self.onPerformAction = onPerformAction
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Tab Strip (Ghostty Minimalist Segmented Tabs)
            HStack(spacing: 2) {
                ForEach(SidebarTab.allCases) { tab in
                    let isSelected = state.activeTab == tab
                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            state.activeTab = tab
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))

                            Text(tab.title)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))

                            // Badges
                            if tab == .serial && !serialWatcher.connectedDevices.isEmpty {
                                Circle()
                                    .fill(Color.mint)
                                    .frame(width: 5, height: 5)
                            } else if tab == .tasks && taskManager.activeCount > 0 {
                                Text("\(taskManager.activeCount)")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 0.5)
                                    .background(isSelected ? Color.white.opacity(0.3) : Color.accentColor.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? Color(nsColor: .controlAccentColor) : Color.clear)
                        )
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))

            Divider()

            // Tab Content
            switch state.activeTab {
            case .commands:
                QuickCommandsView(
                    configuredCommands: configuredCommands,
                    surface: surface,
                    send: send,
                    splitAndSend: splitAndSend
                )
            case .serial:
                SerialInspectorView(
                    surface: surface,
                    onConnect: { command, openInNewTab in
                        handleConnectCommand(command, inNewTab: openInNewTab)
                    },
                    onSplitAndConnect: { command in
                        handleSplitCommand(command)
                    }
                )
            case .sessions:
                SessionManagerView(
                    surface: surface,
                    onConnect: { command, openInNewTab in
                        handleConnectCommand(command, inNewTab: openInNewTab)
                    },
                    onSplitAndConnect: { command in
                        handleSplitCommand(command)
                    }
                )
            case .tasks:
                TasksView(
                    onAttachToTerminal: { command in
                        handleConnectCommand(command, inNewTab: false)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleConnectCommand(_ commandText: String, inNewTab: Bool) {
        guard let surface = surface else { return }
        if inNewTab {
            onPerformAction?("new_tab")
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(180)) {
                let qc = QuickCommand(title: "Connect", command: commandText)
                send(qc, commandText, true, false)
            }
        } else {
            let qc = QuickCommand(title: "Connect", command: commandText)
            send(qc, commandText, true, false)
        }
    }

    private func handleSplitCommand(_ commandText: String) {
        guard let surface = surface else { return }
        onPerformAction?("new_split:right")
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(180)) {
            let qc = QuickCommand(title: "Connect", command: commandText)
            send(qc, commandText, true, false)
        }
    }
}
