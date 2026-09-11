import SwiftUI
import AppKit

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
            vt100Keypad: true
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

                    // Configuration Form matching Screenshot
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

            // Bottom Action Buttons matching Screenshot
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

                    // Open in New Tab (Distinctive Orange/Accent Button from Screenshot)
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
