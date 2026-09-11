import SwiftUI
import AppKit
import Darwin

public struct SerialConnectionConfig: Equatable {
    public var name: String
    public var devicePath: String
    public var baudRate: Int
    public var dataBits: Int
    public var parity: String
    public var stopBits: Double
    public var flowControl: String
    public var closeOnExit: Bool
    public var deleteSendsCtrlH: Bool
    public var vt100Keypad: Bool

    // SecureCRT Hardware Tools: Line and Character delay
    public var lineDelayMs: Int
    public var charDelayMs: Int

    public static func `default`(for path: String, name: String? = nil) -> SerialConnectionConfig {
        let cleanName = name ?? (path as NSString).lastPathComponent.replacingOccurrences(of: "cu.", with: "")
        return SerialConnectionConfig(
            name: cleanName,
            devicePath: path,
            baudRate: 115200,
            dataBits: 8,
            parity: "None",
            stopBits: 1.0,
            flowControl: "None",
            closeOnExit: false,
            deleteSendsCtrlH: false,
            vt100Keypad: true,
            lineDelayMs: 0,
            charDelayMs: 0
        )
    }

    public func buildLaunchCommand() -> String {
        // macOS native standard command to connect to serial port
        return "screen \(devicePath) \(baudRate)"
    }
}

public struct SerialInspectorView: View {
    @ObservedObject var serialWatcher = SerialDeviceWatcher.shared
    @ObservedObject var state = QuickCommandsState.shared
    let surface: Ghostty.SurfaceView?
    let onConnect: (String, Bool) -> Void // (command, openInNewTab)
    var onSplitAndConnect: ((String) -> Void)? = nil

    @State private var availablePorts: [SerialDevice] = []
    @State private var selectedDevice: SerialDevice? = nil
    @State private var config: SerialConnectionConfig = .default(for: "/dev/cu.usbserial", name: "Serial Port")

    // Hardware tools state
    @State private var breakFeedbackMessage: String? = nil
    @State private var isThrottledPasting = false
    @State private var pasteProgressMessage: String? = nil

    init(
        surface: Ghostty.SurfaceView?,
        onConnect: @escaping (String, Bool) -> Void,
        onSplitAndConnect: ((String) -> Void)? = nil
    ) {
        self.surface = surface
        self.onConnect = onConnect
        self.onSplitAndConnect = onSplitAndConnect
    }

    private func refreshPorts() {
        var ports = SerialDeviceWatcher.allAvailablePorts()
        // Ensure connected devices from watcher are prioritized
        for d in serialWatcher.connectedDevices {
            if !ports.contains(where: { $0.bsdPath == d.bsdPath }) {
                ports.insert(d, at: 0)
            }
        }
        availablePorts = ports

        // Match selected device
        if let targetPath = state.selectedSerialDevicePath,
           let match = availablePorts.first(where: { $0.bsdPath == targetPath }) {
            selectDevice(match)
        } else if selectedDevice == nil, let first = availablePorts.first {
            selectDevice(first)
        }
    }

    private func selectDevice(_ dev: SerialDevice) {
        selectedDevice = dev
        state.selectedSerialDevicePath = dev.bsdPath
        config = .default(for: dev.bsdPath, name: dev.name)
    }

    // MARK: - Hardware Break Signal

    private func triggerBreakSignal() {
        let devPath = config.devicePath

        // 1. Send POSIX tcsendbreak to device if accessible
        let fd = open(devPath, O_RDWR | O_NOCTTY | O_NONBLOCK)
        if fd >= 0 {
            tcsendbreak(fd, 0) // duration 0 sends break of 250ms-500ms
            close(fd)
        }

        // 2. In GNU screen sessions, send screen break sequence Ctrl-A + b (\u{01}b)
        surface?.surfaceModel?.sendText("\u{01}b")

        breakFeedbackMessage = "⚡ Break sent (250ms UART Break condition)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if breakFeedbackMessage?.hasPrefix("⚡ Break") == true {
                breakFeedbackMessage = nil
            }
        }
    }

    // MARK: - Throttled Paste (Line & Character Delay)

    private func performThrottledPaste() {
        guard let clipboardText = NSPasteboard.general.string(forType: .string), !clipboardText.isEmpty else {
            pasteProgressMessage = "Clipboard is empty"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { pasteProgressMessage = nil }
            return
        }

        guard let surface = surface else {
            pasteProgressMessage = "No active terminal"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { pasteProgressMessage = nil }
            return
        }

        let lines = clipboardText.components(separatedBy: .newlines)
        let totalLines = lines.count
        let lineDelay = max(config.lineDelayMs, 20)

        isThrottledPasting = true
        pasteProgressMessage = "Pasting 0/\(totalLines)..."

        Task {
            for (idx, line) in lines.enumerated() {
                await MainActor.run {
                    pasteProgressMessage = "Pasting \(idx + 1)/\(totalLines)..."
                    surface.surfaceModel?.sendText(line + "\n")
                }
                try? await Task.sleep(nanoseconds: UInt64(lineDelay) * 1_000_000)
            }

            await MainActor.run {
                isThrottledPasting = false
                pasteProgressMessage = "✓ \(totalLines) lines pasted"
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                pasteProgressMessage = nil
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Serial Connection")
                    .font(.headline)
                Spacer()
                Button {
                    refreshPorts()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Rescan Serial Ports")
                .focusable(false)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Available Serial Ports Section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DETECTED SERIAL PORTS (\(availablePorts.count))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)

                        if availablePorts.isEmpty {
                            Text("No serial devices detected. Plug in a USB-serial adapter.")
                                .font(.caption2)
                                .foregroundStyle(.secondary.opacity(0.8))
                                .padding(.vertical, 4)
                        } else {
                            VStack(spacing: 2) {
                                ForEach(availablePorts) { dev in
                                    let isSel = selectedDevice?.bsdPath == dev.bsdPath
                                    HStack(spacing: 6) {
                                        Image(systemName: dev.isUSB ? "cable.connector" : "cpu")
                                            .font(.system(size: 11))
                                            .foregroundStyle(isSel ? Color.accentColor : Color.secondary)
                                            .frame(width: 14)

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(dev.name)
                                                .font(.system(size: 11, weight: isSel ? .semibold : .regular))
                                                .lineLimit(1)
                                            Text(dev.bsdPath)
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }

                                        Spacer()

                                        if isSel {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(isSel ? Color.accentColor.opacity(0.12) : Color.clear)
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectDevice(dev)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)

                    Divider()

                    // Configuration Form
                    VStack(alignment: .leading, spacing: 12) {
                        // Descriptive Name
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Descriptive name")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("e.g. wlan-debug or router-console", text: $config.name)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                        }

                        // Serial Port Parameters
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SERIAL PORT PARAMETERS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)

                            // Device Path
                            HStack {
                                Text("Device Path")
                                    .font(.system(size: 11))
                                Spacer()
                                Text(config.devicePath)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            // Baud Rate
                            HStack {
                                Text("Baud Rate")
                                    .font(.system(size: 11))
                                Spacer()
                                Picker("", selection: $config.baudRate) {
                                    ForEach(SerialDeviceWatcher.standardBaudRates, id: \.self) { rate in
                                        Text("\(rate)").tag(rate)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 110)
                                .focusable(false)
                            }

                            // Data Bits
                            HStack {
                                Text("Data Bits")
                                    .font(.system(size: 11))
                                Spacer()
                                Picker("", selection: $config.dataBits) {
                                    Text("8").tag(8)
                                    Text("7").tag(7)
                                    Text("6").tag(6)
                                    Text("5").tag(5)
                                }
                                .labelsHidden()
                                .frame(width: 110)
                                .focusable(false)
                            }

                            // Parity
                            HStack {
                                Text("Parity")
                                    .font(.system(size: 11))
                                Spacer()
                                Picker("", selection: $config.parity) {
                                    Text("None").tag("None")
                                    Text("Even").tag("Even")
                                    Text("Odd").tag("Odd")
                                    Text("Mark").tag("Mark")
                                    Text("Space").tag("Space")
                                }
                                .labelsHidden()
                                .frame(width: 110)
                                .focusable(false)
                            }

                            // Stop Bits
                            HStack {
                                Text("Stop Bits")
                                    .font(.system(size: 11))
                                Spacer()
                                Picker("", selection: $config.stopBits) {
                                    Text("1").tag(1.0)
                                    Text("1.5").tag(1.5)
                                    Text("2").tag(2.0)
                                }
                                .labelsHidden()
                                .frame(width: 110)
                                .focusable(false)
                            }

                            // Flow Control
                            HStack {
                                Text("Flow Control")
                                    .font(.system(size: 11))
                                Spacer()
                                Picker("", selection: $config.flowControl) {
                                    Text("None").tag("None")
                                    Text("Hardware (RTS/CTS)").tag("Hardware")
                                    Text("Software (XON/XOFF)").tag("Software")
                                }
                                .labelsHidden()
                                .frame(width: 110)
                                .focusable(false)
                            }
                        }
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)

                        // Hardware Tools Section (SecureCRT Grade)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("HARDWARE TOOLS & PASTE THROTTLING")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)

                            // Break Signal Button
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Send Break Signal")
                                        .font(.system(size: 11, weight: .medium))
                                    Text("Triggers Cisco ROMMON / U-Boot bootloader.")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    triggerBreakSignal()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "bolt.fill")
                                            .font(.system(size: 10))
                                        Text("Send Break")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color.orange.opacity(0.9))
                                    )
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                            }

                            if let msg = breakFeedbackMessage {
                                Text(msg)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.orange)
                                    .padding(.vertical, 2)
                            }

                            Divider()

                            // Paste Throttling
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Line Delay (Slow UARTs)")
                                        .font(.system(size: 11))
                                    Spacer()
                                    Picker("", selection: $config.lineDelayMs) {
                                        Text("None (0ms)").tag(0)
                                        Text("20 ms").tag(20)
                                        Text("50 ms").tag(50)
                                        Text("100 ms").tag(100)
                                        Text("250 ms").tag(250)
                                    }
                                    .labelsHidden()
                                    .frame(width: 120)
                                    .focusable(false)
                                }

                                HStack {
                                    Button {
                                        performThrottledPaste()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "doc.on.clipboard")
                                                .font(.system(size: 10))
                                            Text(isThrottledPasting ? "Pasting..." : "Paste Throttled")
                                                .font(.system(size: 10))
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(isThrottledPasting)
                                    .focusable(false)

                                    if let progress = pasteProgressMessage {
                                        Text(progress)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)

                        // Terminal Settings
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TERMINAL OPTIONS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)

                            HStack {
                                Text("When shell exits")
                                    .font(.system(size: 11))
                                Spacer()
                                Picker("", selection: $config.closeOnExit) {
                                    Text("Don't close terminal").tag(false)
                                    Text("Close terminal").tag(true)
                                }
                                .labelsHidden()
                                .frame(width: 140)
                                .focusable(false)
                            }

                            Toggle("Delete sends Control-H", isOn: $config.deleteSendsCtrlH)
                                .font(.system(size: 11))
                                .focusable(false)

                            Toggle("Allow VT100 application keypad mode", isOn: $config.vt100Keypad)
                                .font(.system(size: 11))
                                .focusable(false)
                        }
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.vertical, 8)
            }

            Divider()

            // Bottom Action Buttons
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button("Restore Defaults") {
                        if let sel = selectedDevice {
                            config = .default(for: sel.bsdPath, name: sel.name)
                        }
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .focusable(false)

                    Spacer()

                    // Connect in Current Tab
                    Button("Connect Here") {
                        let cmd = config.buildLaunchCommand()
                        onConnect(cmd, false)
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .focusable(false)
                }

                HStack(spacing: 8) {
                    // Open in Split
                    if let onSplitAndConnect = onSplitAndConnect {
                        Button("Open in Split") {
                            let cmd = config.buildLaunchCommand()
                            onSplitAndConnect(cmd)
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .focusable(false)
                    }

                    Spacer()

                    // Open in New Tab
                    Button {
                        let cmd = config.buildLaunchCommand()
                        onConnect(cmd, true)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.rectangle")
                                .font(.system(size: 11))
                            Text("Open in New Tab")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.orange)
                        )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            refreshPorts()
        }
        .onChange(of: serialWatcher.connectedDevices) { _ in
            refreshPorts()
        }
        .onChange(of: state.selectedSerialDevicePath) { newPath in
            if let newPath, let match = availablePorts.first(where: { $0.bsdPath == newPath }) {
                selectDevice(match)
            }
        }
    }
}
