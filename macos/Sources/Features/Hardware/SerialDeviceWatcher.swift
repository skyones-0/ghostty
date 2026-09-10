import Foundation
import Combine
import IOKit
import IOKit.serial

/// A representation of a connected serial communication device.
struct SerialDevice: Identifiable, Equatable, Hashable {
    var id: String { bsdPath }
    let bsdPath: String
    let name: String
    let isUSB: Bool
    let connectedAt: Date
}

/// Event-driven watcher for serial devices using IOKit notifications.
/// Operates with 0% idle CPU by registering Mach notification ports with the main CFRunLoop.
@MainActor
final class SerialDeviceWatcher: ObservableObject {
    static let shared = SerialDeviceWatcher()

    @Published private(set) var connectedDevices: [SerialDevice] = []
    @Published var activeAlert: SerialDevice?
    @Published var selectedBaudRate: Int = 115200

    static let standardBaudRates = [9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600]

    private var notifyPort: IONotificationPortRef?
    private var matchedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0
    private var autoDismissTask: Task<Void, Never>?
    private var initialScanCompleted = false

    private init() {
        setupIOKitWatcher()
    }

    deinit {
        if matchedIterator != 0 {
            IOObjectRelease(matchedIterator)
        }
        if terminatedIterator != 0 {
            IOObjectRelease(terminatedIterator)
        }
        if let notifyPort = notifyPort {
            IONotificationPortDestroy(notifyPort)
        }
    }

    /// Set up IOKit service matching notifications for BSD serial ports.
    private func setupIOKitWatcher() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.notifyPort = port

        let runLoopSource = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // 1. Notification for device arrival
        let matchDictArrival = IOServiceMatching(kIOSerialBSDServiceValue) as NSMutableDictionary
        matchDictArrival[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes

        let matchCallback: IOServiceMatchingCallback = { userData, iterator in
            guard let userData = userData else { return }
            let watcher = Unmanaged<SerialDeviceWatcher>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                watcher.handleMatchedDevices(iterator: iterator)
            }
        }

        let krArrival = IOServiceAddMatchingNotification(
            port,
            kIOMatchedNotification,
            matchDictArrival,
            matchCallback,
            selfPtr,
            &matchedIterator
        )

        if krArrival == KERN_SUCCESS {
            // Drain initial iterator to prime notification and populate current devices
            drainIterator(matchedIterator, isInitialScan: true)
        }

        // 2. Notification for device removal
        let matchDictRemoval = IOServiceMatching(kIOSerialBSDServiceValue) as NSMutableDictionary
        matchDictRemoval[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes

        let termCallback: IOServiceMatchingCallback = { userData, iterator in
            guard let userData = userData else { return }
            let watcher = Unmanaged<SerialDeviceWatcher>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                watcher.handleTerminatedDevices(iterator: iterator)
            }
        }

        let krRemoval = IOServiceAddMatchingNotification(
            port,
            kIOTerminatedNotification,
            matchDictRemoval,
            termCallback,
            selfPtr,
            &terminatedIterator
        )

        if krRemoval == KERN_SUCCESS {
            drainIterator(terminatedIterator, isInitialScan: true)
        }

        initialScanCompleted = true
    }

    private func drainIterator(_ iterator: io_iterator_t, isInitialScan: Bool) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let device = extractSerialDevice(from: service) {
                if !connectedDevices.contains(where: { $0.bsdPath == device.bsdPath }) {
                    connectedDevices.append(device)
                    if !isInitialScan && device.isUSB {
                        triggerAlert(for: device)
                    }
                }
            }
        }
    }

    private func handleMatchedDevices(iterator: io_iterator_t) {
        drainIterator(iterator, isInitialScan: !initialScanCompleted)
    }

    private func handleTerminatedDevices(iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let path = getCalloutPath(from: service) {
                connectedDevices.removeAll { $0.bsdPath == path }
                if activeAlert?.bsdPath == path {
                    dismissAlert()
                }
            }
        }
    }

    private func triggerAlert(for device: SerialDevice) {
        activeAlert = device
        autoDismissTask?.cancel()
        autoDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if self.activeAlert == device {
                self.dismissAlert()
            }
        }
    }

    func dismissAlert() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        activeAlert = nil
    }

    private func getCalloutPath(from service: io_service_t) -> String? {
        guard let prop = IORegistryEntryCreateCFProperty(
            service,
            kIOCalloutDeviceKey as CFString,
            kCFAllocatorDefault,
            0
        ) else { return nil }
        return prop.takeRetainedValue() as? String
    }

    private func extractSerialDevice(from service: io_service_t) -> SerialDevice? {
        guard let bsdPath = getCalloutPath(from: service) else { return nil }

        // Filter out built-in virtual or bluetooth serial ports
        let lower = bsdPath.lowercased()
        if lower.contains("bluetooth") || lower.contains("debug-console") || lower.contains("wlan-debug") {
            return nil
        }

        let isUSB = lower.contains("usb") || lower.contains("modem") || lower.contains("wch") || lower.contains("uart")

        // Traverse IORegistry parents to discover friendly USB product name
        var friendlyName = (bsdPath as NSString).lastPathComponent
        var current = service
        IOObjectRetain(current)
        while current != 0 {
            if let prod = IORegistryEntryCreateCFProperty(current, "USB Product Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String ??
                          IORegistryEntryCreateCFProperty(current, "Product Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
                friendlyName = prod
                IOObjectRelease(current)
                break
            }
            var parent: io_registry_entry_t = 0
            if IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS {
                IOObjectRelease(current)
                current = parent
            } else {
                IOObjectRelease(current)
                break
            }
        }

        return SerialDevice(
            bsdPath: bsdPath,
            name: friendlyName,
            isUSB: isUSB,
            connectedAt: Date()
        )
    }
}
