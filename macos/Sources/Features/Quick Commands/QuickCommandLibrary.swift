import Combine
import Foundation

/// One library per application, independent of config reloads and window state.
@MainActor
final class QuickCommandLibrary: ObservableObject {
    static var defaultURL: URL {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let dotConfigDir = home.appendingPathComponent(".config", isDirectory: true).appendingPathComponent("ghostty", isDirectory: true)
        let dotConfigFile = dotConfigDir.appendingPathComponent("quick-commands.json")

        // Auto-migrate from legacy Application Support if ~/.config file does not exist yet
        if !fileManager.fileExists(atPath: dotConfigFile.path) {
            let legacyCandidates = [
                fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty")
                    .appendingPathComponent("quick-commands.json"),
                fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("com.mitchellh.ghostty.debug")
                    .appendingPathComponent("quick-commands.json")
            ]
            for candidate in legacyCandidates {
                if fileManager.fileExists(atPath: candidate.path) {
                    try? fileManager.createDirectory(at: dotConfigDir, withIntermediateDirectories: true)
                    try? fileManager.copyItem(at: candidate, to: dotConfigFile)
                    break
                }
            }
        }
        return dotConfigFile
    }

    static let shared = QuickCommandLibrary(url: defaultURL)

    struct Document: Codable {
        var version = 1
        var commands: [QuickCommand]
        var groups: [String]? = []
        var groupIcons: [String: String]? = [:]
    }

    @Published private(set) var commands: [QuickCommand] = []
    @Published private(set) var customGroups: [String] = []
    @Published private(set) var groupIcons: [String: String] = [:]
    @Published private(set) var errorMessage: String?
    private(set) var canWrite = true
    let url: URL

    private var fileWatcher: DispatchSourceFileSystemObject?

    init(url: URL) {
        self.url = url
        reload()
        startWatching()
    }

    deinit {
        fileWatcher?.cancel()
    }

    private func startWatching() {
        stopWatching()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.reload()
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                self.startWatching()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.fileWatcher = source
    }

    private func stopWatching() {
        fileWatcher?.cancel()
        fileWatcher = nil
    }

    func reload() {
        do {
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch CocoaError.fileReadNoSuchFile {
                commands = []
                customGroups = []
                canWrite = true
                errorMessage = nil
                return
            }
            let document = try JSONDecoder().decode(Document.self, from: data)
            guard document.version == 1,
                  Set(document.commands.map(\.id)).count == document.commands.count,
                  document.commands.allSatisfy({ $0.validationError == nil }) else {
                throw LibraryError.invalidDocument
            }
            commands = document.commands
            customGroups = (document.groups ?? []).sorted()
            groupIcons = document.groupIcons ?? [:]
            canWrite = true
            errorMessage = nil
        } catch {
            canWrite = false
            errorMessage = "Could not load quick commands at \(url.path): \(error.localizedDescription)"
        }
    }

    func icon(for group: String) -> String? {
        if let explicit = groupIcons[group], !explicit.isEmpty {
            return explicit
        }
        return GroupIconCatalog.defaultIcon(for: group)
    }

    @discardableResult
    func addGroup(_ group: String, icon: String? = nil) -> Bool {
        let trimmed = group.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        var updated = customGroups
        if !updated.contains(trimmed) {
            updated.append(trimmed)
            updated.sort()
        }
        var icons = groupIcons
        if let icon = icon, !icon.isEmpty {
            icons[trimmed] = icon
        }
        return persist(commands, groups: updated, icons: icons)
    }

    @discardableResult
    func save(_ command: QuickCommand) -> Bool {
        guard command.validationError == nil else {
            errorMessage = command.validationError
            return false
        }
        var updated = commands
        if let index = updated.firstIndex(where: { $0.id == command.id }) {
            updated[index] = command
        } else {
            updated.append(command)
        }
        var groups = customGroups
        if let grp = command.group?.trimmingCharacters(in: .whitespaces), !grp.isEmpty, !groups.contains(grp) {
            groups.append(grp)
            groups.sort()
        }
        return persist(updated, groups: groups)
    }

    @discardableResult
    func delete(_ command: QuickCommand) -> Bool {
        persist(commands.filter { $0.id != command.id })
    }

    @discardableResult
    func renameGroup(oldName: String, newName: String, newIcon: String? = nil) -> Bool {
        let trimmedNew = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmedNew.isEmpty else { return false }
        var groups = customGroups
        if oldName != trimmedNew {
            groups = groups.map { $0 == oldName ? trimmedNew : $0 }
            if !groups.contains(trimmedNew) {
                groups.append(trimmedNew)
            }
            groups.removeAll { $0 == oldName }
            groups = Array(Set(groups)).sorted()
        }

        var icons = groupIcons
        icons.removeValue(forKey: oldName)
        if let newIcon, !newIcon.isEmpty {
            icons[trimmedNew] = newIcon
        }

        let updatedCommands = commands.map { cmd -> QuickCommand in
            if cmd.group == oldName {
                var copy = cmd
                copy.group = trimmedNew
                return copy
            }
            return cmd
        }
        return persist(updatedCommands, groups: groups, icons: icons)
    }

    @discardableResult
    func deleteGroup(_ group: String) -> Bool {
        var groups = customGroups
        groups.removeAll { $0 == group }
        var icons = groupIcons
        icons.removeValue(forKey: group)

        let updatedCommands = commands.map { cmd -> QuickCommand in
            if cmd.group == group {
                var copy = cmd
                copy.group = nil
                return copy
            }
            return cmd
        }
        return persist(updatedCommands, groups: groups, icons: icons)
    }

    private func persist(_ updated: [QuickCommand], groups: [String]? = nil, icons: [String: String]? = nil) -> Bool {
        guard canWrite else { return false }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let docGroups = groups ?? customGroups
            let docIcons = icons ?? groupIcons
            let data = try encoder.encode(Document(commands: updated, groups: docGroups, groupIcons: docIcons))
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            commands = updated
            customGroups = docGroups
            groupIcons = docIcons
            errorMessage = nil
            if fileWatcher == nil {
                startWatching()
            }
            return true
        } catch {
            errorMessage = "Could not save quick commands: \(error.localizedDescription)"
            return false
        }
    }

    private enum LibraryError: LocalizedError {
        case invalidDocument

        var errorDescription: String? { "Unsupported or invalid quick commands library." }
    }
}
