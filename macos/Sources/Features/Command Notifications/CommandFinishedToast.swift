import SwiftUI

/// Information about a completed terminal command for presentation in toasts.
struct CommandAlertInfo: Identifiable, Equatable {
    let id: UUID
    let name: String
    let commandLine: String?
    let duration: TimeInterval
    let finishedAt: Date

    init(
        name: String,
        commandLine: String?,
        duration: TimeInterval,
        finishedAt: Date = Date(),
        id: UUID = UUID()
    ) {
        self.id = id
        self.name = name
        self.commandLine = commandLine
        self.duration = duration
        self.finishedAt = finishedAt
    }

    var formattedDuration: String {
        let total = Int(duration)
        let hours = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, mins)
        } else if mins > 0 {
            return String(format: "%dm %02ds", mins, secs)
        } else {
            return "\(total)s"
        }
    }
}

/// Ephemeral floating toast displayed when a long-running terminal command finishes.
struct CommandFinishedToast: View {
    let alert: CommandAlertInfo
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Success icon with subtle green tint
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.mint)

            // Command info
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(alert.name)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)

                    Text("(\(alert.formattedDuration))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)

                    Text("• Finished")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.mint)
                }

                if let cmd = alert.commandLine, !cmd.isEmpty, cmd != alert.name {
                    Text(cmd)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Process completed successfully")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 3)
        )
    }
}
