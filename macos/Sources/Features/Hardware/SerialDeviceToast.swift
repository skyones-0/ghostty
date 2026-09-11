import SwiftUI

/// Ephemeral floating toast displayed when a USB serial device is detected.
struct SerialDeviceToast: View {
    let device: SerialDevice
    @Binding var baudRate: Int
    let onConnect: (SerialDevice, Int) -> Void
    let onDismiss: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            // Clickable Info leading to Sidebar Serial Inspector
            Button {
                QuickCommandsState.shared.selectedSerialDevicePath = device.bsdPath
                QuickCommandsState.shared.showTab(.serial)
                onDismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "cable.connector")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.mint)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(device.name)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }

                        Text(device.bsdPath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Click to configure serial connection in sidebar")

            // Baud rate menu
            Menu(content: {
                ForEach(SerialDeviceWatcher.standardBaudRates, id: \.self) { rate in
                    Button(action: { baudRate = rate }, label: {
                        if rate == baudRate {
                            Label("\(rate) baud", systemImage: "checkmark")
                        } else {
                            Text("\(rate) baud")
                        }
                    })
                }
            }, label: {
                Text("\(baudRate)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
            })
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Connect button
            Button(action: {
                onConnect(device, baudRate)
            }, label: {
                Text("Connect")
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
        .onHover { isHovered = $0 }
    }
}
