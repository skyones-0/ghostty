import SwiftUI
import AppKit

@MainActor
public final class SessionLogger: ObservableObject {
    public static let shared = SessionLogger()

    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var currentSessionName: String = ""
    @Published public private(set) var currentLogURL: URL? = nil
    @Published public private(set) var recordedBytes: Int = 0
    @Published public private(set) var elapsedTimeFormatted: String = "00:00"

    // Configuration options
    @Published public var prependTimestamps: Bool = true
    @Published public var stripANSI: Bool = true

    private var fileHandle: FileHandle? = nil
    private var timer: Timer? = nil
    private var startTime: Date? = nil
    private let dateFormatter: DateFormatter
    private let timestampFormatter: DateFormatter

    private init() {
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"

        self.timestampFormatter = DateFormatter()
        self.timestampFormatter.dateFormat = "[yyyy-MM-dd HH:mm:ss.SSS] "
    }

    public var logsDirectoryURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let spectreLogs = docs.appendingPathComponent("Spectre Pro Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: spectreLogs, withIntermediateDirectories: true)
        return spectreLogs
    }

    public func startRecording(sessionName: String) {
        if isRecording {
            _ = stopRecording()
        }

        let cleanName = sessionName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let filename = "\(dateFormatter.string(from: Date()))_\(cleanName.isEmpty ? "session" : cleanName).log"
        let logURL = logsDirectoryURL.appendingPathComponent(filename)

        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }

        self.fileHandle = handle
        self.currentSessionName = cleanName.isEmpty ? "Terminal Session" : cleanName
        self.currentLogURL = logURL
        self.recordedBytes = 0
        self.isRecording = true
        self.startTime = Date()
        self.elapsedTimeFormatted = "00:00"

        // Initial Header
        let header = "=== Spectre Pro Session Log: \(currentSessionName) ===\n=== Started: \(Date()) ===\n\n"
        if let data = header.data(using: .utf8) {
            handle.write(data)
            recordedBytes += data.count
        }

        // Duration timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let start = self.startTime else { return }
                let elapsed = Int(Date().timeIntervalSince(start))
                let minutes = elapsed / 60
                let seconds = elapsed % 60
                self.elapsedTimeFormatted = String(format: "%02d:%02d", minutes, seconds)
            }
        }
    }

    public func log(text: String) {
        guard isRecording, let handle = fileHandle, !text.isEmpty else { return }

        var output = text
        if stripANSI {
            output = cleanANSIEscapeSequences(from: output)
        }

        if prependTimestamps {
            let ts = timestampFormatter.string(from: Date())
            let lines = output.components(separatedBy: .newlines)
            output = lines.map { "\(ts)\($0)" }.joined(separator: "\n")
        }

        if let data = output.data(using: .utf8) {
            handle.write(data)
            recordedBytes += data.count
        }
    }

    public func stopRecording() -> URL? {
        guard isRecording else { return nil }

        let footer = "\n=== Session Ended: \(Date()) (Bytes: \(recordedBytes)) ===\n"
        if let data = footer.data(using: .utf8) {
            fileHandle?.write(data)
        }

        try? fileHandle?.close()
        fileHandle = nil

        timer?.invalidate()
        timer = nil

        let finalURL = currentLogURL
        isRecording = false
        startTime = nil
        return finalURL
    }

    public func openLogsFolder() {
        NSWorkspace.shared.open(logsDirectoryURL)
    }

    public func revealCurrentLogInFinder() {
        if let url = currentLogURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            openLogsFolder()
        }
    }

    private func cleanANSIEscapeSequences(from input: String) -> String {
        // Regex to strip standard ANSI / VT100 / xterm color and cursor control sequences
        let pattern = #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return input
        }
        let range = NSRange(location: 0, length: input.utf16.count)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: "")
    }
}

// MARK: - Live Recording Overlay Indicator

public struct SessionRecordingIndicator: View {
    @ObservedObject private var logger = SessionLogger.shared
    @State private var isBlinking = false

    public init() {}

    public var body: some View {
        if logger.isRecording {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(isBlinking ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isBlinking)

                Text("REC [\(logger.elapsedTimeFormatted)]")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.red)

                Text(logger.currentSessionName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: 100)

                Button {
                    _ = logger.stopRecording()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Stop Session Recording")

                Button {
                    logger.revealCurrentLogInFinder()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reveal Log File in Finder")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
            )
            .overlay(
                Capsule()
                    .stroke(Color.red.opacity(0.4), lineWidth: 1)
            )
            .onAppear {
                isBlinking = true
            }
        }
    }
}
