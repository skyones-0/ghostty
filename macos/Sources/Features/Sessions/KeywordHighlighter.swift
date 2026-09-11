import SwiftUI
import AppKit

public enum KeywordCategory: String, CaseIterable, Identifiable {
    case error = "Errors & Failures"
    case success = "Active & Up States"
    case warning = "Warnings & Timeouts"
    case networkIP = "IPv4 Addresses"
    case networkMAC = "MAC Addresses"

    public var id: String { rawValue }

    public var color: Color {
        switch self {
        case .error: return .red
        case .success: return .green
        case .warning: return .orange
        case .networkIP: return .cyan
        case .networkMAC: return .purple
        }
    }

    public var iconName: String {
        switch self {
        case .error: return "exclamationmark.octagon.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .networkIP: return "network"
        case .networkMAC: return "cable.connector"
        }
    }
}

public struct KeywordRule: Identifiable, Equatable {
    public var id = UUID()
    public var category: KeywordCategory
    public var pattern: String
    public var isRegex: Bool

    public init(category: KeywordCategory, pattern: String, isRegex: Bool = false) {
        self.category = category
        self.pattern = pattern
        self.isRegex = isRegex
    }
}

public struct KeywordMatchItem: Identifiable, Equatable {
    public var id: String { "\(category.rawValue)_\(text)" }
    public var text: String
    public var category: KeywordCategory
    public var count: Int
}

@MainActor
public final class KeywordHighlighter: ObservableObject {
    public static let shared = KeywordHighlighter()

    @Published public var isEnabled: Bool = true
    @Published public private(set) var detectedMatches: [KeywordMatchItem] = []
    @Published public private(set) var totalMatchesCount: Int = 0

    private var rules: [KeywordRule] = []
    private var compiledRegexes: [(rule: KeywordRule, regex: NSRegularExpression)] = []

    private init() {
        setupDefaultRules()
        compileRules()
    }

    private func setupDefaultRules() {
        // SecureCRT Network / Systems Engineer Highlighting Set
        rules = [
            KeywordRule(category: .error, pattern: #"\b(ERROR|FAIL|FAILED|FATAL|CRITICAL|DOWN|DENIED|REJECTED|ERR|SHUTDOWN|PANIC)\b"#, isRegex: true),
            KeywordRule(category: .success, pattern: #"\b(UP|ESTABLISHED|SUCCESS|OK|ONLINE|CONNECTED|ACTIVE|READY|PASSED|RUNNING)\b"#, isRegex: true),
            KeywordRule(category: .warning, pattern: #"\b(WARNING|WARN|TIMEOUT|RETRY|DROPPED|SLOW|DEGRADED|ALERT)\b"#, isRegex: true),
            KeywordRule(category: .networkIP, pattern: #"\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b"#, isRegex: true),
            KeywordRule(category: .networkMAC, pattern: #"\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b"#, isRegex: true)
        ]
    }

    private func compileRules() {
        compiledRegexes.removeAll()
        for rule in rules {
            if let rx = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]) {
                compiledRegexes.append((rule, rx))
            }
        }
    }

    public func scan(text: String) {
        guard isEnabled, !text.isEmpty else {
            detectedMatches = []
            totalMatchesCount = 0
            return
        }

        var countsByCategoryAndWord: [String: (text: String, category: KeywordCategory, count: Int)] = [:]
        let range = NSRange(location: 0, length: text.utf16.count)

        for (rule, regex) in compiledRegexes {
            let matches = regex.matches(in: text, options: [], range: range)
            for m in matches {
                if let r = Range(m.range, in: text) {
                    let word = String(text[r])
                    let key = "\(rule.category.rawValue)_\(word.uppercased())"
                    if let existing = countsByCategoryAndWord[key] {
                        countsByCategoryAndWord[key] = (existing.text, rule.category, existing.count + 1)
                    } else {
                        countsByCategoryAndWord[key] = (word, rule.category, 1)
                    }
                }
            }
        }

        let sorted = countsByCategoryAndWord.values.map {
            KeywordMatchItem(text: $0.text, category: $0.category, count: $0.count)
        }.sorted { $0.count > $1.count }

        self.detectedMatches = sorted
        self.totalMatchesCount = sorted.reduce(0) { $0 + $1.count }
    }
}

// MARK: - Keyword Highlight HUD Badge

public struct KeywordHighlightHUD: View {
    @ObservedObject private var highlighter = KeywordHighlighter.shared
    @State private var showDetailsPopover = false

    public init() {}

    public var body: some View {
        HStack(spacing: 4) {
            Button {
                showDetailsPopover.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "highlighter")
                        .font(.system(size: 10))
                        .foregroundStyle(highlighter.isEnabled ? Color.yellow : Color.secondary)

                    if highlighter.isEnabled && highlighter.totalMatchesCount > 0 {
                        Text("\(highlighter.totalMatchesCount)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                )
            }
            .buttonStyle(.plain)
            .help("Keyword Highlighting (SecureCRT Style)")
            .popover(isPresented: $showDetailsPopover) {
                KeywordMatchesPopoverView()
            }
        }
    }
}

private struct KeywordMatchesPopoverView: View {
    @ObservedObject private var highlighter = KeywordHighlighter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Keyword Highlighting")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $highlighter.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            if highlighter.detectedMatches.isEmpty {
                Text(highlighter.isEnabled ? "No matching keywords currently on screen." : "Highlighting is disabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(highlighter.detectedMatches) { item in
                            HStack(spacing: 6) {
                                Image(systemName: item.category.iconName)
                                    .font(.system(size: 10))
                                    .foregroundStyle(item.category.color)

                                Text(item.text)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .lineLimit(1)

                                Spacer()

                                Text("\(item.count)x")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(item.text, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Copy \(item.text)")
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(item.category.color.opacity(0.1))
                            )
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}
