import SwiftUI
import AppKit

@MainActor
public final class ExpectSendEngine: ObservableObject {
    public static let shared = ExpectSendEngine()

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var currentStatus: String? = nil

    private var currentTask: Task<Void, Never>? = nil

    private init() {}

    public func start(
        rules: [ExpectSendRule],
        textReader: @escaping () -> String,
        textSender: @escaping (String) -> Void
    ) {
        cancel()
        guard !rules.isEmpty else { return }

        isRunning = true
        currentStatus = "Expect/Send: Started (1/\(rules.count))"

        currentTask = Task {
            for (index, rule) in rules.enumerated() {
                if Task.isCancelled { break }

                let stepNum = index + 1
                let expectedPattern = rule.expect.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !expectedPattern.isEmpty else { continue }

                await MainActor.run {
                    self.currentStatus = "Waiting for '\(expectedPattern)' (\(stepNum)/\(rules.count))..."
                }

                // Poll text buffer up to 15 seconds
                var matched = false
                let maxAttempts = 60 // 60 * 250ms = 15s
                for _ in 0..<maxAttempts {
                    if Task.isCancelled { break }
                    try? await Task.sleep(nanoseconds: 250_000_000)

                    let currentText = await MainActor.run { textReader() }
                    if currentText.localizedCaseInsensitiveContains(expectedPattern) {
                        matched = true
                        break
                    }
                }

                if Task.isCancelled { break }

                if matched {
                    await MainActor.run {
                        self.currentStatus = "Matched '\(expectedPattern)'. Sending response..."
                        var toSend = rule.send
                        if !toSend.hasSuffix("\n") {
                            toSend += "\n"
                        }
                        textSender(toSend)
                    }
                    // Wait 500ms before checking next rule
                    try? await Task.sleep(nanoseconds: 500_000_000)
                } else {
                    await MainActor.run {
                        self.currentStatus = "Timeout waiting for '\(expectedPattern)'"
                    }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    break
                }
            }

            await MainActor.run {
                self.isRunning = false
                self.currentStatus = nil
            }
        }
    }

    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isRunning = false
        currentStatus = nil
    }
}
