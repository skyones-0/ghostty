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

/// Unified section picker dropdown styled to match Ghostty's minimalist aesthetic.
public struct SidebarSectionPicker: View {
    @ObservedObject private var state = QuickCommandsState.shared
    @ObservedObject private var serialWatcher = SerialDeviceWatcher.shared
    @ObservedObject private var taskManager = BackgroundTaskManager.shared
    @State private var isHovered: Bool = false

    public init() {}

    public var body: some View {
        Menu {
            ForEach(SidebarTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        state.activeTab = tab
                    }
                } label: {
                    HStack {
                        Label(tab.longTitle, systemImage: tab.iconName)
                        if tab == .serial && !serialWatcher.connectedDevices.isEmpty {
                            Text("(\(serialWatcher.connectedDevices.count))")
                        } else if tab == .tasks && taskManager.activeCount > 0 {
                            Text("(\(taskManager.activeCount))")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: state.activeTab.iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text(state.activeTab.longTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                // Indicator badges next to title
                if state.activeTab == .serial && !serialWatcher.connectedDevices.isEmpty {
                    Circle()
                        .fill(Color.mint)
                        .frame(width: 6, height: 6)
                } else if state.activeTab == .tasks && taskManager.activeCount > 0 {
                    Text("\(taskManager.activeCount)")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.25))
                        .clipShape(Capsule())
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovered = $0 }
        .help("Switch Section")
        .focusable(false)
    }
}
