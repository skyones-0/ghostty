import SwiftUI
import AppKit

private final class QuickCommandsKeyMonitor: ObservableObject {
    private var monitor: Any?
    var isModalPresented: Bool = false
    var onMove: ((Int) -> Void)?
    var onExecute: (() -> Void)?
    var onInsert: (() -> Void)?
    var onCancel: (() -> Void)?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            // If a modal sheet is presented, let the sheet handle all keys
            guard !self.isModalPresented else { return event }

            // Check if key window matches
            guard let window = event.window, window == NSApp.keyWindow else { return event }

            // If the terminal surface has focus, pass event through untouched!
            if window.firstResponder is Ghostty.OSSurfaceView {
                return event
            }

            switch event.keyCode {
            case 126: // Up Arrow
                self.onMove?(-1)
                return nil
            case 125: // Down Arrow
                self.onMove?(1)
                return nil
            case 36: // Return / Enter
                if event.modifierFlags.contains(.option) {
                    self.onInsert?()
                } else {
                    self.onExecute?()
                }
                return nil
            case 53: // Escape
                self.onCancel?()
                return nil
            default:
                return event
            }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        stop()
    }
}

struct QuickCommandsView: View {
    let configuredCommands: [QuickCommand]
    let surface: Ghostty.SurfaceView?
    let send: (QuickCommand, String?, Bool, Bool) -> Void
    var splitAndSend: ((QuickCommand, String?, Bool) -> Void)?

    @ObservedObject private var library = QuickCommandLibrary.shared
    @StateObject private var processMonitor = TerminalProcessMonitor()
    @StateObject private var keyMonitor = QuickCommandsKeyMonitor()

    @ObservedObject private var state = QuickCommandsState.shared
    @State private var editing: QuickCommand?
    @State private var parameterizing: QuickCommand?
    @State private var isCreatingGroup: Bool = false
    @State private var renamingGroup: GroupRenameItem? = nil
    @State private var deletingGroup: String? = nil
    @State private var isSearchVisible: Bool = false

    @FocusState private var isSearchFocused: Bool

    private var allGroups: [String] {
        var groups = Set<String>()
        for cmd in configuredCommands {
            if let grp = cmd.group?.trimmingCharacters(in: .whitespaces), !grp.isEmpty {
                groups.insert(grp)
            }
        }
        for cmd in library.commands {
            if let grp = cmd.group?.trimmingCharacters(in: .whitespaces), !grp.isEmpty {
                groups.insert(grp)
            }
        }
        for grp in library.customGroups where !grp.isEmpty {
            groups.insert(grp)
        }
        return groups.sorted()
    }

    private func matchesFilter(_ cmd: QuickCommand) -> Bool {
        if let selectedGroup = state.selectedGroup, !selectedGroup.isEmpty {
            if cmd.group != selectedGroup { return false }
        }
        let query = state.searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty { return true }
        if cmd.title.lowercased().contains(query) { return true }
        if cmd.command.lowercased().contains(query) { return true }
        if let grp = cmd.group?.lowercased(), grp.contains(query) { return true }
        return false
    }

    private var filteredCommands: [(command: QuickCommand, configured: Bool)] {
        var results: [(command: QuickCommand, configured: Bool)] = []
        for cmd in configuredCommands where matchesFilter(cmd) {
            results.append((cmd, true))
        }
        for cmd in library.commands where matchesFilter(cmd) {
            results.append((cmd, false))
        }
        return results
    }

    private func countForGroup(_ group: String) -> Int {
        var count = 0
        for cmd in configuredCommands where cmd.group == group { count += 1 }
        for cmd in library.commands where cmd.group == group { count += 1 }
        return count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
                Text("Quick Commands")
                    .font(.headline)

                Spacer()

                // Background Jobs Indicator
                BackgroundJobsIndicator(monitor: processMonitor)

                // Search toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isSearchVisible.toggle()
                    }
                    if isSearchVisible {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isSearchFocused = true
                        }
                    } else {
                        isSearchFocused = false
                        state.searchText = ""
                        if let surface {
                            surface.window?.makeFirstResponder(surface)
                        }
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSearchVisible ? Color.primary : Color.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(isSearchVisible ? "Hide Search" : "Search Commands")
                .accessibilityLabel("Search Commands")

                // Broadcast toggle (SecureCRT Send to All)
                Button {
                    state.isBroadcast.toggle()
                } label: {
                    Image(systemName: state.isBroadcast ? "wave.3.backward.circle.fill" : "wave.3.backward")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(state.isBroadcast ? Color.orange : Color.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(state.isBroadcast ? "Broadcast active (send to all splits)" : "Broadcast: Send to all splits")
                .accessibilityLabel("Broadcast to all splits")
                .accessibilityValue(state.isBroadcast ? "On" : "Off")

                // Add command or group (minimalist Ghostty-proportioned icon)
                Menu {
                    Button {
                        editing = QuickCommand(title: "", command: "", group: state.selectedGroup)
                    } label: {
                        Label("New Command", systemImage: "apple.terminal")
                    }

                    Button {
                        isCreatingGroup = true
                    } label: {
                        Label("New Group", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("Add Command or Group")
                .accessibilityLabel("Add Command or Group")
                .disabled(!library.canWrite)
                .focusable(false)
            }

            // SecureCRT-style Horizontal Group Tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    GroupTabButton(
                        title: "All",
                        isSelected: state.selectedGroup == nil,
                        count: configuredCommands.count + library.commands.count
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) { state.selectedGroup = nil }
                    }

                    ForEach(allGroups, id: \.self) { grp in
                        GroupTabButton(
                            title: grp,
                            isSelected: state.selectedGroup == grp,
                            count: countForGroup(grp)
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) { state.selectedGroup = grp }
                        }
                        .contextMenu {
                            Button {
                                renamingGroup = GroupRenameItem(name: grp)
                            } label: {
                                Label("Rename Group…", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                deletingGroup = grp
                            } label: {
                                Label("Delete Group", systemImage: "trash")
                            }
                        }
                    }

                    Button {
                        isCreatingGroup = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 10, weight: .medium))
                            Text("Group")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                        .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Create new command group")
                }
                .padding(.vertical, 2)
            }

            // Search Bar & Keyboard shortcuts helper
            if isSearchVisible {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Search...", text: $state.searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .focused($isSearchFocused)
                        .onSubmit {
                            if NSEvent.modifierFlags.contains(.option) {
                                insertFocusedCommand()
                            } else {
                                executeFocusedCommand()
                            }
                        }
                        .onExitCommand {
                            isSearchFocused = false
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isSearchVisible = false
                                state.searchText = ""
                            }
                            if let surface {
                                surface.window?.makeFirstResponder(surface)
                            }
                        }
                    if !state.searchText.isEmpty {
                        Button {
                            state.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if state.isBroadcast {
                HStack(spacing: 4) {
                    Image(systemName: "wave.3.backward")
                        .foregroundStyle(.orange)
                    Text("Broadcast active: commands will be sent to all splits.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }

            if let error = library.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                Button("Reload Library") { library.reload() }
            }

            if configuredCommands.isEmpty && library.commands.isEmpty {
                Text("No quick commands yet. Add a command here or define quick-command in your Ghostty configuration.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else if filteredCommands.isEmpty {
                Text("No commands match your search.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(filteredCommands.enumerated()), id: \.element.command.id) { index, item in
                                QuickCommandCard(
                                    command: item.command,
                                    configured: item.configured,
                                    surface: surface,
                                    shortcutNumber: index < 9 ? index + 1 : nil,
                                    isHighlighted: state.selectedIndex == index,
                                    onSelect: {
                                        // Do not lock persistent focus on click
                                    },
                                    onExecute: {
                                        handleExecute(item.command)
                                    },
                                    onInsert: {
                                        handleInsert(item.command)
                                    },
                                    onSplitAndRun: {
                                        handleSplitAndRun(item.command)
                                    },
                                    onDuplicate: { editing = item.command.duplicate() },
                                    onEdit: { editing = item.command },
                                    onDelete: { library.delete(item.command) }
                                )
                                .id(index)
                            }
                        }
                    }
                    .onChange(of: state.selectedIndex) { newIndex in
                        if let newIndex {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                scrollProxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            processMonitor.setSurfaceView(surface)
            state.selectedIndex = nil
            isSearchFocused = false
            keyMonitor.onMove = { delta in navigateSelection(delta) }
            keyMonitor.onExecute = { executeFocusedCommand() }
            keyMonitor.onInsert = { insertFocusedCommand() }
            keyMonitor.onCancel = {
                isSearchFocused = false
                if isSearchVisible {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isSearchVisible = false
                        state.searchText = ""
                    }
                }
                state.selectedIndex = nil
                if let surface {
                    surface.window?.makeFirstResponder(surface)
                }
            }
            keyMonitor.start()
        }
        .onDisappear {
            keyMonitor.stop()
        }
        .onChange(of: state.searchText) { _ in
            state.selectedIndex = nil
        }
        .onChange(of: state.selectedGroup) { _ in
            state.selectedIndex = nil
        }
        .onChange(of: surface) { newSurface in
            processMonitor.setSurfaceView(newSurface)
        }
        .onChange(of: editing) { keyMonitor.isModalPresented = ($0 != nil || parameterizing != nil || isCreatingGroup) }
        .onChange(of: parameterizing) { keyMonitor.isModalPresented = (editing != nil || $0 != nil || isCreatingGroup) }
        .onChange(of: isCreatingGroup) { keyMonitor.isModalPresented = (editing != nil || parameterizing != nil || $0 || renamingGroup != nil) }
        .onChange(of: renamingGroup?.name) { keyMonitor.isModalPresented = (editing != nil || parameterizing != nil || isCreatingGroup || $0 != nil) }
        .sheet(item: $editing) { command in
            QuickCommandEditor(command: command, existingGroups: allGroups, library: library)
        }
        .sheet(isPresented: $isCreatingGroup) {
            QuickGroupCreationModal(library: library) { newGroup in
                state.selectedGroup = newGroup
            }
        }
        .sheet(item: $renamingGroup) { item in
            QuickGroupRenameModal(groupName: item.name, library: library) { newName in
                if state.selectedGroup == item.name {
                    state.selectedGroup = newName
                }
            }
        }
        .confirmationDialog(
            "Delete Group '\(deletingGroup ?? "")'?",
            isPresented: Binding(
                get: { deletingGroup != nil },
                set: { if !$0 { deletingGroup = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Group", role: .destructive) {
                if let grp = deletingGroup {
                    if state.selectedGroup == grp {
                        state.selectedGroup = nil
                    }
                    library.deleteGroup(grp)
                }
                deletingGroup = nil
            }
            Button("Cancel", role: .cancel) {
                deletingGroup = nil
            }
        } message: {
            Text("Commands belonging to this group will not be deleted; they will remain available under 'All'.")
        }
        .sheet(item: $parameterizing) { command in
            QuickCommandParameterModal(
                command: command,
                clipboard: NSPasteboard.general.string(forType: .string),
                selection: surface?.accessibilitySelectedText()
            ) { customText, execute in
                send(command, customText, execute, state.isBroadcast)
                isSearchFocused = false
                if let surface {
                    surface.window?.makeFirstResponder(surface)
                }
            }
        }
    }

    private func navigateSelection(_ delta: Int) {
        let count = filteredCommands.count
        guard count > 0 else { return }
        let current = state.selectedIndex ?? (delta > 0 ? -1 : 0)
        state.selectedIndex = (current + delta + count) % count
    }

    private func executeFocusedCommand() {
        guard let idx = state.selectedIndex, idx >= 0 && idx < filteredCommands.count else { return }
        handleExecute(filteredCommands[idx].command)
    }

    private func insertFocusedCommand() {
        guard let idx = state.selectedIndex, idx >= 0 && idx < filteredCommands.count else { return }
        handleInsert(filteredCommands[idx].command)
    }

    private func triggerNumberShortcut(_ num: Int) {
        let index = num - 1
        guard index >= 0 && index < filteredCommands.count else { return }
        handleExecute(filteredCommands[index].command)
    }

    private func handleExecute(_ command: QuickCommand) {
        let clipboard = NSPasteboard.general.string(forType: .string)
        let selection = surface?.accessibilitySelectedText()
        if command.manualPlaceholders.isEmpty {
            let resolved = command.autoResolvedCommand(clipboard: clipboard, selection: selection)
            send(command, resolved, true, state.isBroadcast)
            isSearchFocused = false
            if let surface {
                surface.window?.makeFirstResponder(surface)
            }
        } else {
            parameterizing = command
        }
    }

    private func handleInsert(_ command: QuickCommand) {
        let clipboard = NSPasteboard.general.string(forType: .string)
        let selection = surface?.accessibilitySelectedText()
        if command.manualPlaceholders.isEmpty {
            let resolved = command.autoResolvedCommand(clipboard: clipboard, selection: selection)
            send(command, resolved, false, state.isBroadcast)
            isSearchFocused = false
            if let surface {
                surface.window?.makeFirstResponder(surface)
            }
        } else {
            parameterizing = command
        }
    }

    private func handleSplitAndRun(_ command: QuickCommand) {
        let clipboard = NSPasteboard.general.string(forType: .string)
        let selection = surface?.accessibilitySelectedText()
        if command.manualPlaceholders.isEmpty {
            let resolved = command.autoResolvedCommand(clipboard: clipboard, selection: selection)
            splitAndSend?(command, resolved, true)
        } else {
            parameterizing = command
        }
    }
}

private func iconForPreset(name: String, commandText: String = "") -> String {
    let lower = (name + " " + commandText).lowercased()
    if lower == "all" { return "tray.2.fill" }
    if lower.contains("ssh") || lower.contains("server") || lower.contains("vps") || lower.contains("host") {
        return "server.rack"
    }
    if lower.contains("git") || lower.contains("github") || lower.contains("commit") || lower.contains("branch") {
        return "arrow.triangle.branch"
    }
    if lower.contains("linux") || lower.contains("ubuntu") || lower.contains("debian") || lower.contains("arch") {
        return "terminal.fill"
    }
    if lower.contains("docker") || lower.contains("container") || lower.contains("k8s") || lower.contains("compose") {
        return "shippingbox.fill"
    }
    if lower.contains("ai") || lower.contains("agent") || lower.contains("claude") || lower.contains("codex") || lower.contains("llm") || lower.contains("agy") {
        return "sparkles"
    }
    if lower.contains("db") || lower.contains("database") || lower.contains("sql") || lower.contains("mongo") || lower.contains("redis") {
        return "cylinder.split.1x2.fill"
    }
    if lower.contains("kill") || lower.contains("stop") {
        return "stop.circle"
    }
    if lower.contains("log") || lower.contains("tail") || lower.contains("journal") {
        return "doc.text.magnifyingglass"
    }
    if lower.contains("cloud") || lower.contains("aws") || lower.contains("gcp") || lower.contains("azure") {
        return "cloud.fill"
    }
    if lower.contains("curl") || lower.contains("http") || lower.contains("api") || lower.contains("web") {
        return "network"
    }
    return "folder.fill"
}

private func cleanPresetTitle(_ rawTitle: String) -> String {
    var text = rawTitle.trimmingCharacters(in: .whitespaces)
    while let first = text.unicodeScalars.first, first.properties.isEmoji && !first.properties.isASCIIHexDigit {
        text.removeFirst()
        text = text.trimmingCharacters(in: .whitespaces)
    }
    return text.isEmpty ? rawTitle : text
}

private struct GroupTabButton: View {
    let title: String
    let isSelected: Bool
    var count: Int?
    let action: () -> Void

    private var iconName: String {
        iconForPreset(name: title)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)

                Text(cleanPresetTitle(title))
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))

                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(isSelected ? Color.white.opacity(0.3) : Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isSelected
                    ? Color.accentColor
                    : Color(nsColor: .controlBackgroundColor)
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

private struct BackgroundJobsIndicator: View {
    @ObservedObject var monitor: TerminalProcessMonitor
    @State private var showPopover = false

    var body: some View {
        if !monitor.recentExits.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption2)
                Text("\(monitor.recentExits.joined(separator: ", ")) finished")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.green.opacity(0.12))
            .cornerRadius(6)
            .transition(.opacity)
        } else if !monitor.runningJobs.isEmpty {
            Button {
                showPopover.toggle()
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                    Text("\(monitor.runningJobs.count) bg")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Terminal Processes")
                            .font(.headline)
                        Spacer()
                        Text("\(monitor.runningJobs.count) active")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    ForEach(monitor.runningJobs) { job in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(job.isForeground ? Color.accentColor : Color.orange)
                                .frame(width: 6, height: 6)
                            Text(job.name)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            Text("PID \(job.pid)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Kill", role: .destructive) {
                                monitor.terminateJob(job)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption2)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(12)
                .frame(minWidth: 230)
            }
            .help("Active background processes on this terminal")
        }
    }
}

private struct QuickCommandCard: View, Equatable {
    let command: QuickCommand
    let configured: Bool
    let surface: Ghostty.SurfaceView?
    var shortcutNumber: Int?
    var isHighlighted: Bool = false
    var onSelect: (() -> Void)? = nil
    let onExecute: () -> Void
    let onInsert: () -> Void
    var onSplitAndRun: (() -> Void)?
    let onDuplicate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    static func == (lhs: QuickCommandCard, rhs: QuickCommandCard) -> Bool {
        lhs.command == rhs.command &&
        lhs.configured == rhs.configured &&
        lhs.shortcutNumber == rhs.shortcutNumber &&
        lhs.isHighlighted == rhs.isHighlighted
    }

    private var isDisabled: Bool {
        surface == nil || surface?.surface == nil || surface?.readonly == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                // Clickable Title Button (executes on click)
                Button {
                    isPressed = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        isPressed = false
                    }
                    onSelect?()
                    onExecute()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: iconForPreset(name: (command.group ?? "") + " " + command.title, commandText: command.command))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 14)

                        Text(command.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isDisabled ? Color.secondary : Color.primary)
                            .lineLimit(1)

                        if let grp = command.group, !grp.isEmpty {
                            Text(cleanPresetTitle(grp))
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(4)
                                .foregroundStyle(Color.secondary)
                        }

                        if !command.manualPlaceholders.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 8))
                                Text("<\(command.manualPlaceholders.first ?? "")>")
                                    .font(.system(size: 9))
                            }
                            .foregroundStyle(Color.accentColor)
                        } else if command.command.contains("{clipboard}") || command.command.contains("<clipboard>") {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .help("Auto-injects clipboard")
                        } else if command.command.contains("{selection}") || command.command.contains("<selection>") {
                            Image(systemName: "selection.pin.in.out")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .help("Auto-injects selected text")
                        }

                        Spacer()

                        if let num = shortcutNumber {
                            Text("⌘\(num)")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.secondary.opacity(0.7))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(isDisabled)
                .help("Execute: \(command.command)")

                // Split & Run Action (always present in layout to avoid content resizing, opacity toggled)
                if let onSplitAndRun = onSplitAndRun {
                    Button {
                        onSplitAndRun()
                    } label: {
                        Image(systemName: "rectangle.split.2x1")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Split terminal right and run")
                    .opacity(isHovered ? 1.0 : 0.0)
                    .disabled(!isHovered)
                }

                // Context Menu (...)
                Menu {
                    Button("Insert in prompt") { onInsert() }
                    if onSplitAndRun != nil {
                        Button("Run in new split") { onSplitAndRun?() }
                    }
                    Button("Duplicate") { onDuplicate() }
                    if !configured {
                        Button("Edit…") { onEdit() }
                        Button("Delete", role: .destructive) { onDelete() }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11))
                        .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .focusable(false)
                .fixedSize()
                .accessibilityLabel("Options for \(command.title)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isPressed
                            ? Color.primary.opacity(0.12)
                            : (isHighlighted
                                ? Color.primary.opacity(0.08)
                                : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
                    )
            )
            .contentShape(Rectangle())
            .onHover { inside in
                isHovered = inside
            }
            .focusable(false)
            Divider()
                .padding(.top, 2)
        }
    }
}

private struct QuickGroupCreationModal: View {
    @ObservedObject var library: QuickCommandLibrary
    let onCreated: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var groupName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Command Group")
                .font(.headline)

            Text("Create a group to organize commands (e.g. Cisco, Linux, Docker, Git):")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Group name", text: $groupName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create Group") {
                    let trimmed = groupName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        library.addGroup(trimmed)
                        onCreated(trimmed)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 360)
    }
}

private struct GroupRenameItem: Identifiable {
    var id: String { name }
    let name: String
}

private struct QuickGroupRenameModal: View {
    let groupName: String
    @ObservedObject var library: QuickCommandLibrary
    let onRenamed: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename Group")
                .font(.headline)

            Text("Enter a new name for '\(groupName)'. All commands in this group will be updated:")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Group name", text: $newName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    let trimmed = newName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty && trimmed != groupName {
                        library.renameGroup(oldName: groupName, newName: trimmed)
                        onRenamed(trimmed)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || newName.trimmingCharacters(in: .whitespaces) == groupName)
            }
        }
        .padding(18)
        .frame(width: 360)
        .onAppear {
            newName = groupName
        }
    }
}

private struct QuickCommandParameterModal: View {
    let command: QuickCommand
    let clipboard: String?
    let selection: String?
    let onSend: (String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var values: [String: String] = [:]

    private var resolvedCommand: String {
        command.autoResolvedCommand(clipboard: clipboard, selection: selection, values: values)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Parameters: \(command.title)")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text("Enter values for command variables:")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(command.manualPlaceholders, id: \.self) { placeholder in
                    HStack {
                        Text("<\(placeholder)>")
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 90, alignment: .leading)
                        TextField("Value for \(placeholder)", text: Binding(
                            get: { values[placeholder] ?? "" },
                            set: { values[placeholder] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Preview:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(resolvedCommand)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(4)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Insert") {
                    onSend(resolvedCommand, false)
                    dismiss()
                }
                Button("Execute") {
                    onSend(resolvedCommand, true)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 440)
    }
}

private struct QuickCommandEditor: View {
    @State var command: QuickCommand
    let existingGroups: [String]
    @ObservedObject var library: QuickCommandLibrary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(command.title.isEmpty ? "New Quick Command" : "Edit Quick Command")
                .font(.headline)

            TextField("Name", text: $command.title)
            TextField("Command (supports <var>, {clipboard}, {selection})", text: $command.command)
                .font(.system(.body, design: .monospaced))

            VStack(alignment: .leading, spacing: 4) {
                Text("Group (optional):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("e.g. Linux, Cisco, Git", text: Binding(
                        get: { command.group ?? "" },
                        set: { command.group = $0.isEmpty ? nil : $0 }
                    ))
                    if !existingGroups.isEmpty {
                        Menu("Choose...") {
                            Button("No group") { command.group = nil }
                            ForEach(existingGroups, id: \.self) { grp in
                                Button(grp) { command.group = grp }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }

            Toggle("Allow immediate execution", isOn: Binding(
                get: { command.action == .execute },
                set: { command.action = $0 ? .execute : .insert }
            ))

            if let error = command.validationError {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
            if let error = library.errorMessage {
                Text(error).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if library.save(command) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(command.validationError != nil || !library.canWrite)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// Keeps the terminal subtree in the same position and identity as the panel
/// opens and closes. Resizing changes layout only, never the terminal split tree.
struct QuickCommandsLayout<Terminal: View, Sidebar: View>: View {
    @Binding var isShowing: Bool
    @Binding var width: CGFloat
    @ViewBuilder var terminal: () -> Terminal
    @ViewBuilder var sidebar: () -> Sidebar
    @State private var dragStart: CGFloat?
    @State private var hoveringDivider = false

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                terminal()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if isShowing {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 5)
                        .onHover { inside in
                            guard inside != hoveringDivider else { return }
                            hoveringDivider = inside
                            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                        }
                        .onDisappear {
                            if hoveringDivider {
                                NSCursor.pop()
                                hoveringDivider = false
                            }
                            dragStart = nil
                        }
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStart == nil { dragStart = bounded(width, total: geometry.size.width) }
                                width = bounded((dragStart ?? width) - value.translation.width, total: geometry.size.width)
                            }
                            .onEnded { _ in dragStart = nil })
                        .accessibilityLabel("Quick Commands Width")
                        .accessibilityValue("\(Int(width)) points")
                        .accessibilityAdjustableAction { direction in
                            width = bounded(width + (direction == .increment ? 20 : -20), total: geometry.size.width)
                        }
                    sidebar().frame(width: bounded(width, total: geometry.size.width))
                }
            }
        }
    }

    private func bounded(_ value: CGFloat, total: CGFloat) -> CGFloat {
        min(max(220, value), max(220, total - 165))
    }
}
