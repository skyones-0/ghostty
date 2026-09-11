import SwiftUI
import AppKit

public struct SavedSession: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var folder: String
    public var host: String
    public var user: String?
    public var port: Int?
    public var sessionType: String // "ssh", "console", "telnet"

    public init(
        id: UUID = UUID(),
        name: String,
        folder: String = "SSH",
        host: String,
        user: String? = nil,
        port: Int? = 22,
        sessionType: String = "ssh"
    ) {
        self.id = id
        self.name = name
        self.folder = folder
        self.host = host
        self.user = user
        self.port = port
        self.sessionType = sessionType
    }

    public func buildConnectCommand() -> String {
        switch sessionType.lowercased() {
        case "telnet":
            let p = port ?? 23
            return "telnet \(host) \(p)"
        case "console":
            return "screen \(host) \(port ?? 115200)"
        default:
            var cmd = "ssh "
            if let p = port, p != 22 {
                cmd += "-p \(p) "
            }
            if let u = user, !u.isEmpty {
                cmd += "\(u)@"
            }
            cmd += host
            return cmd
        }
    }
}

@MainActor
public final class SessionLibrary: ObservableObject {
    public static let shared = SessionLibrary()

    @Published public var sessions: [SavedSession] = []

    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let ghosttyDir = appSupport.appendingPathComponent("com.mitchellh.ghostty", isDirectory: true)
        try? FileManager.default.createDirectory(at: ghosttyDir, withIntermediateDirectories: true)
        self.fileURL = ghosttyDir.appendingPathComponent("sessions.json")
        load()
    }

    public func load() {
        var loaded: [SavedSession] = []
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([SavedSession].self, from: data) {
            loaded = list
        }

        // Auto-discover hosts from ~/.ssh/config if not already added
        let sshHosts = discoverSSHConfigHosts()
        for h in sshHosts {
            if !loaded.contains(where: { $0.host == h.host && $0.name == h.name }) {
                loaded.append(h)
            }
        }

        if loaded.isEmpty {
            // Provide sensible defaults matching user's enterprise network context
            loaded = [
                SavedSession(name: "Router Gateway", folder: "Local", host: "192.168.1.1", user: "admin"),
                SavedSession(name: "Fortigate FW", folder: "SSH", host: "10.0.0.1", user: "admin"),
                SavedSession(name: "OCI VM 01", folder: "SSH", host: "oracle-cloud.internal", user: "opc")
            ]
            save(loaded)
        }

        self.sessions = loaded
    }

    public func save(_ list: [SavedSession]? = nil) {
        let toSave = list ?? sessions
        self.sessions = toSave
        if let data = try? JSONEncoder().encode(toSave) {
            try? data.write(to: fileURL)
        }
    }

    public func add(_ s: SavedSession) {
        sessions.append(s)
        save()
    }

    public func delete(_ s: SavedSession) {
        sessions.removeAll { $0.id == s.id }
        save()
    }

    private func discoverSSHConfigHosts() -> [SavedSession] {
        let sshConfigURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
        guard let content = try? String(contentsOf: sshConfigURL, encoding: .utf8) else { return [] }

        var results: [SavedSession] = []
        var currentHost: String? = nil
        var currentHostName: String? = nil
        var currentUser: String? = nil
        var currentPort: Int? = nil

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let val = parts[1].trimmingCharacters(in: .whitespaces)

            if key == "host" {
                if let name = currentHost, !name.contains("*") && !name.contains("?") {
                    results.append(SavedSession(
                        name: name,
                        folder: "SSH Config",
                        host: currentHostName ?? name,
                        user: currentUser,
                        port: currentPort ?? 22
                    ))
                }
                currentHost = val
                currentHostName = nil
                currentUser = nil
                currentPort = nil
            } else if key == "hostname" {
                currentHostName = val
            } else if key == "user" {
                currentUser = val
            } else if key == "port" {
                currentPort = Int(val)
            }
        }

        if let name = currentHost, !name.contains("*") && !name.contains("?") {
            results.append(SavedSession(
                name: name,
                folder: "SSH Config",
                host: currentHostName ?? name,
                user: currentUser,
                port: currentPort ?? 22
            ))
        }

        return results
    }
}

public struct SessionManagerView: View {
    @ObservedObject var library = SessionLibrary.shared
    let surface: Ghostty.SurfaceView?
    let onConnect: (String, Bool) -> Void
    var onSplitAndConnect: ((String) -> Void)? = nil

    @State private var searchText: String = ""
    @State private var isCreatingSession = false
    @State private var collapsedFolders: Set<String> = []

    init(
        surface: Ghostty.SurfaceView?,
        onConnect: @escaping (String, Bool) -> Void,
        onSplitAndConnect: ((String) -> Void)? = nil
    ) {
        self.surface = surface
        self.onConnect = onConnect
        self.onSplitAndConnect = onSplitAndConnect
    }

    private var allFolders: [String] {
        let set = Set(library.sessions.map { $0.folder })
        return Array(set).sorted()
    }

    private var filteredSessions: [SavedSession] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return library.sessions
        }
        let q = searchText.lowercased()
        return library.sessions.filter {
            $0.name.lowercased().contains(q) || $0.host.lowercased().contains(q) || $0.folder.lowercased().contains(q)
        }
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Text("Session Manager")
                    .font(.headline)
                Spacer()
                Button {
                    isCreatingSession = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Add New Session")
                .focusable(false)
            }

            // Search
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Filter sessions...", text: $searchText)
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

            // Folders Tree (SecureCRT Tree Layout)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(allFolders, id: \.self) { folder in
                        let sessionsInFolder = filteredSessions.filter { $0.folder == folder }
                        if !sessionsInFolder.isEmpty {
                            let isCollapsed = collapsedFolders.contains(folder)
                            VStack(alignment: .leading, spacing: 2) {
                                // Folder Header
                                Button {
                                    if isCollapsed {
                                        collapsedFolders.remove(folder)
                                    } else {
                                        collapsedFolders.insert(folder)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 10)
                                        Image(systemName: "folder.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.accentColor)
                                        Text(folder.uppercased())
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.secondary)
                                        Text("(\(sessionsInFolder.count))")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary.opacity(0.7))
                                        Spacer()
                                    }
                                    .padding(.vertical, 3)
                                }
                                .buttonStyle(.plain)
                                .focusable(false)

                                if !isCollapsed {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(sessionsInFolder) { session in
                                            SessionRowItem(
                                                session: session,
                                                onConnectHere: { onConnect(session.buildConnectCommand(), false) },
                                                onConnectNewTab: { onConnect(session.buildConnectCommand(), true) },
                                                onConnectSplit: { onSplitAndConnect?(session.buildConnectCommand()) },
                                                onDelete: { library.delete(session) }
                                            )
                                        }
                                    }
                                    .padding(.leading, 14)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $isCreatingSession) {
            NewSessionModal { session in
                library.add(session)
            }
        }
    }
}

private struct SessionRowItem: View {
    let session: SavedSession
    let onConnectHere: () -> Void
    let onConnectNewTab: () -> Void
    let onConnectSplit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: session.sessionType == "console" ? "cable.connector" : "server.rack")
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(session.host)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isHovered {
                Button {
                    onConnectNewTab()
                } label: {
                    Image(systemName: "plus.rectangle")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Connect in New Tab")
                .focusable(false)
            }

            Menu {
                Button("Connect in Current Tab") { onConnectHere() }
                Button("Open in New Tab") { onConnectNewTab() }
                Button("Open in Split") { onConnectSplit() }
                Divider()
                Button("Copy Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.buildConnectCommand(), forType: .string)
                }
                Button("Delete Session", role: .destructive) { onDelete() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(isHovered ? 0.9 : 0.0))
                    .frame(width: 16, height: 16)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .focusable(false)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onConnectHere() }
    }
}

private struct NewSessionModal: View {
    let onSave: (SavedSession) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var folder: String = "SSH"
    @State private var host: String = ""
    @State private var user: String = ""
    @State private var port: String = "22"
    @State private var sessionType: String = "ssh"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Session")
                .font(.headline)

            VStack(alignment: .leading, spacing: 3) {
                Text("Session Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Cisco Switch or Web Server", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Folder / Group")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g. Production or Local", text: $folder)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Protocol")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $sessionType) {
                        Text("SSH").tag("ssh")
                        Text("Telnet").tag("telnet")
                        Text("Console").tag("console")
                    }
                    .labelsHidden()
                }
                .frame(width: 100)
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Host / IP Address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("hostname or IP", text: $host)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Port")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("22", text: $port)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(width: 70)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Username (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. root, admin, ubuntu", text: $user)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .focusable(false)
                Button("Create Session") {
                    let trimmedName = name.trimmingCharacters(in: .whitespaces)
                    let trimmedHost = host.trimmingCharacters(in: .whitespaces)
                    if !trimmedName.isEmpty && !trimmedHost.isEmpty {
                        let session = SavedSession(
                            name: trimmedName,
                            folder: folder.trimmingCharacters(in: .whitespaces).isEmpty ? "SSH" : folder.trimmingCharacters(in: .whitespaces),
                            host: trimmedHost,
                            user: user.trimmingCharacters(in: .whitespaces).isEmpty ? nil : user.trimmingCharacters(in: .whitespaces),
                            port: Int(port) ?? 22,
                            sessionType: sessionType
                        )
                        onSave(session)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || host.trimmingCharacters(in: .whitespaces).isEmpty)
                .focusable(false)
            }
        }
        .padding(18)
        .frame(width: 380)
    }
}
