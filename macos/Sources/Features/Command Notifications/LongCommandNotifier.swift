import Foundation
import UserNotifications
import AppKit

/// Intelligently notifies the user when long-running terminal commands (>15s) complete while Ghostty is in the background.
@MainActor
final class LongCommandNotifier {
    static let shared = LongCommandNotifier()

    private struct ActiveCommand {
        let name: String
        let commandLine: String?
        let startTime: Date
        let surfaceUUID: UUID
    }

    private var activeCommands: [UUID: ActiveCommand] = [:]
    private let thresholdSeconds: TimeInterval = 10.0

    private init() {
        requestAuthorization()
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Record the start of a foreground command.
    func commandDidStart(name: String, commandLine: String?, surfaceUUID: UUID) {
        // Ensure notification permissions are requested
        requestAuthorization()

        // Only record if not already tracking for this surface
        if activeCommands[surfaceUUID] == nil {
            activeCommands[surfaceUUID] = ActiveCommand(
                name: name,
                commandLine: commandLine,
                startTime: Date(),
                surfaceUUID: surfaceUUID
            )
        }
    }

    /// Process completion of a foreground command. If elapsed time exceeds the threshold
    /// and the surface/window is not active in the foreground, post a native notification.
    func commandDidFinish(surfaceUUID: UUID, isFocused: Bool) {
        guard let command = activeCommands.removeValue(forKey: surfaceUUID) else { return }

        let duration = Date().timeIntervalSince(command.startTime)
        guard duration >= thresholdSeconds else { return }

        // Only notify if window/surface is not actively focused or Ghostty is in background
        let isAppActive = NSApp.isActive
        let shouldNotify = !isFocused || !isAppActive

        if shouldNotify {
            postNotification(for: command, duration: duration)
        }
    }

    private func postNotification(for command: ActiveCommand, duration: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Command Completed"

        let formattedTime = formatDuration(duration)
        let displayName = command.name
        content.subtitle = "\(displayName) (\(formattedTime))"

        if let cmdLine = command.commandLine, !cmdLine.isEmpty, cmdLine != displayName {
            content.body = cmdLine
        } else {
            content.body = "Process exited successfully"
        }

        content.sound = .default
        content.userInfo = [
            "surface": command.surfaceUUID.uuidString,
            "requireFocus": false
        ]

        let request = UNNotificationRequest(
            identifier: "command_finish_\(UUID().uuidString)",
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("[Ghostty] Error posting command notification: %@", error.localizedDescription)
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, remainingMinutes)
        } else if minutes > 0 {
            return String(format: "%dm %02ds", minutes, remainingSeconds)
        } else {
            return "\(totalSeconds)s"
        }
    }
}
