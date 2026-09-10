import SwiftUI

/// Ephemeral floating toast displayed when a process in the terminal begins listening on a local port.
struct LocalPortToast: View {
    let portInfo: LocalPortInfo
    let onDismiss: () -> Void

    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: "network")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.cyan)

            // Info
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("Port :\(String(portInfo.port))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)

                    Text("(\(portInfo.processName))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Text(portInfo.url.absoluteString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Open in browser button
            Button(action: {
                NSWorkspace.shared.open(portInfo.url)
            }, label: {
                Text("Open")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.85))
                    )
            })
            .buttonStyle(.plain)

            // Copy URL button
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(portInfo.url.absoluteString, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    copied = false
                }
            }, label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(copied ? .mint : .secondary)
                    .padding(5)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            })
            .buttonStyle(.plain)

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
