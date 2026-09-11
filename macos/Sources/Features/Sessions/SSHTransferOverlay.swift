import SwiftUI
import AppKit

public struct SSHTransferOverlay: View {
    @ObservedObject private var manager = SSHTransferManager.shared

    public init() {}

    public var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // Active Transfer Pill
            if let active = manager.activeTransfer {
                HStack(spacing: 8) {
                    Image(systemName: active.isUpload ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundStyle(active.isUpload ? Color.cyan : Color.green)
                        .font(.system(size: 13))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(active.detailText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        // Smooth progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.primary.opacity(0.15))
                                    .frame(height: 3)

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(active.isUpload ? Color.cyan : Color.green)
                                    .frame(width: geo.size.width * CGFloat(active.percentage), height: 3)
                                    .animation(.linear(duration: 0.2), value: active.percentage)
                            }
                        }
                        .frame(width: 130, height: 3)
                    }

                    Button {
                        manager.cancelActiveTransfer()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel Transfer")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                )
                .overlay(
                    Capsule()
                        .stroke(active.isUpload ? Color.cyan.opacity(0.4) : Color.green.opacity(0.4), lineWidth: 1)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Completed Toast
            if let toast = manager.completedToast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                        .font(.system(size: 12))

                    Text(toast.isUpload ? "Uploaded \(toast.fileName)" : "Downloaded \(toast.fileName)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !toast.isUpload {
                        Button("Finder") {
                            manager.revealInFinder(url: toast.localURL)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        Button("Open") {
                            manager.openFile(url: toast.localURL)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                    }

                    Button {
                        manager.completedToast = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                )
                .overlay(
                    Capsule()
                        .stroke(Color.green.opacity(0.4), lineWidth: 1)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}
