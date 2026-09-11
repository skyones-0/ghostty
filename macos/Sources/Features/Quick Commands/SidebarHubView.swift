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

    @State private var hoveredTab: SidebarTab? = nil

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
            // Top Tab Strip (Ghostty Minimalist Segmented 4-Icon Bar)
            HStack(spacing: 3) {
                ForEach(SidebarTab.allCases) { tab in
                    let isSelected = state.activeTab == tab
                    let isHovered = hoveredTab == tab
                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            state.activeTab = tab
                        }
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 12, weight: (isSelected || (tab == .tasks && taskManager.activeCount > 0)) ? .semibold : .regular))
                                .foregroundStyle((tab == .tasks && taskManager.activeCount > 0) ? Color.black : (isSelected ? Color.primary : Color.secondary))
                                .frame(maxWidth: .infinity, minHeight: 24)

                            // Status indicators / Badges
                            if tab == .serial && !serialWatcher.connectedDevices.isEmpty {
                                Circle()
                                    .fill(Color.mint)
                                    .frame(width: 6, height: 6)
                                    .padding(.trailing, 6)
                                    .padding(.top, 3)
                            } else if tab == .tasks && taskManager.activeCount > 0 {
                                Text("\(taskManager.activeCount)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Color.black)
                                    .padding(.horizontal, 3.5)
                                    .padding(.vertical, 0.5)
                                    .background(Color.white.opacity(0.85))
                                    .clipShape(Capsule())
                                    .padding(.trailing, 3)
                                    .padding(.top, 2)
                            }
                        }
                        .contentShape(Rectangle())
                        .background(
                            ZStack {
                                if tab == .tasks && taskManager.activeCount > 0 {
                                    GhosttyOverlayBackground(cornerRadius: 6, isPermanent: true)
                                } else if isSelected {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.primary.opacity(0.12))
                                } else if isHovered {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.primary.opacity(0.06))
                                }
                            }
                        )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .onHover { hovering in
                        if hovering {
                            hoveredTab = tab
                        } else if hoveredTab == tab {
                            hoveredTab = nil
                        }
                    }
                    .help(tab.longTitle)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.75))

            Divider().opacity(0.4)

            // Tab Content
            Group {
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
