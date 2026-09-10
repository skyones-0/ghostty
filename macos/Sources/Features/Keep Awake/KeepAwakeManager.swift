import AppKit
import Foundation
import IOKit.pwr_mgt
import OSLog
import UserNotifications

/// Manages system sleep prevention using native macOS IOKit power management assertions.
final class KeepAwakeManager: NSObject, ObservableObject {
    static let shared = KeepAwakeManager()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
        category: String(describing: KeepAwakeManager.self)
    )

    enum Duration: Equatable {
        case off
        case indefinitely
        case hours(Int)

        var timeInterval: TimeInterval? {
            switch self {
            case .off, .indefinitely:
                return nil
            case .hours(let h):
                return TimeInterval(h * 3600)
            }
        }
    }

    @Published private(set) var activeDuration: Duration = .off
    @Published private(set) var expirationDate: Date?
    @Published var preventDisplaySleep: Bool {
        didSet {
            UserDefaults.ghostty.set(preventDisplaySleep, forKey: "KeepAwakePreventDisplaySleep")
            if isActive {
                applyAssertions()
            }
        }
    }

    var isActive: Bool {
        activeDuration != .off
    }

    private var systemAssertionID: IOPMAssertionID = 0
    private var displayAssertionID: IOPMAssertionID = 0
    private var countdownTimer: Timer?

    private weak var parentMenuItem: NSMenuItem?
    private weak var submenu: NSMenu?

    override private init() {
        self.preventDisplaySleep = UserDefaults.ghostty.bool(forKey: "KeepAwakePreventDisplaySleep")
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        countdownTimer?.invalidate()
        releaseAssertions()
    }

    // MARK: - Activation & Deactivation

    @MainActor
    func activate(duration: Duration) {
        if duration == .off {
            deactivate()
            return
        }

        self.activeDuration = duration
        if let interval = duration.timeInterval {
            self.expirationDate = Date().addingTimeInterval(interval)
        } else {
            self.expirationDate = nil
        }

        applyAssertions()
        startTimerIfNeeded()
        updateMenu()
        Self.logger.info("Keep Awake activated with duration: \(String(describing: duration))")
    }

    @MainActor
    func deactivate() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        releaseAssertions()
        activeDuration = .off
        expirationDate = nil
        updateMenu()
        Self.logger.info("Keep Awake deactivated")
    }

    // MARK: - Power Assertions (IOKit)

    private func applyAssertions() {
        releaseAssertions()

        guard isActive else { return }

        // Prevent idle system sleep
        var sysID: IOPMAssertionID = 0
        let sysRes = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Ghostty Keep Awake" as CFString,
            &sysID
        )

        if sysRes == kIOReturnSuccess {
            self.systemAssertionID = sysID
            Self.logger.debug("Acquired system sleep assertion ID: \(sysID)")
        } else {
            Self.logger.error("Failed to create system sleep assertion: \(sysRes)")
        }

        // Prevent idle display sleep if requested
        if preventDisplaySleep {
            var dispID: IOPMAssertionID = 0
            let dispRes = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Ghostty Keep Awake (Display)" as CFString,
                &dispID
            )

            if dispRes == kIOReturnSuccess {
                self.displayAssertionID = dispID
                Self.logger.debug("Acquired display sleep assertion ID: \(dispID)")
            } else {
                Self.logger.error("Failed to create display sleep assertion: \(dispRes)")
            }
        }
    }

    private func releaseAssertions() {
        if systemAssertionID != 0 {
            IOPMAssertionRelease(systemAssertionID)
            systemAssertionID = 0
        }
        if displayAssertionID != 0 {
            IOPMAssertionRelease(displayAssertionID)
            displayAssertionID = 0
        }
    }

    // MARK: - Timer & Expiration

    private func startTimerIfNeeded() {
        countdownTimer?.invalidate()
        countdownTimer = nil

        guard expirationDate != nil else { return }

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let exp = self.expirationDate, Date() >= exp {
                    self.timerDidExpire()
                } else {
                    self.updateMenu()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.countdownTimer = timer
    }

    @MainActor
    private func timerDidExpire() {
        deactivate()
        notifyExpiration()
    }

    private func notifyExpiration() {
        let content = UNMutableNotificationContent()
        content.title = "Ghostty Keep Awake"
        content.body = "Keep Awake duration has expired. System sleep is no longer prevented."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "ghostty.keepawake.expired",
            content: content,
            trigger: nil
        )

        let logger = Self.logger
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                logger.error("Failed to post Keep Awake expiration notification: \(error.localizedDescription)")
            }
        }
    }

    @objc private func workspaceDidWake(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let exp = self.expirationDate, Date() >= exp {
                self.timerDidExpire()
            } else {
                self.updateMenu()
            }
        }
    }

    // MARK: - Menu Setup & Formatting

    var formattedRemainingTime: String? {
        guard let exp = expirationDate else {
            return isActive ? "Active" : nil
        }
        let remaining = max(0, Int(exp.timeIntervalSinceNow))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    var detailedRemainingStatus: String {
        guard isActive else { return "Status: Inactive" }
        guard let exp = expirationDate else { return "Status: Active (Indefinitely)" }
        let remaining = max(0, Int(exp.timeIntervalSinceNow))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60

        if hours > 0 {
            return "Status: Active (\(hours)h \(minutes)m remaining)"
        } else if minutes > 0 {
            return "Status: Active (\(minutes)m \(seconds)s remaining)"
        } else {
            return "Status: Active (\(seconds)s remaining)"
        }
    }

    @MainActor
    func setup(menuItem: NSMenuItem?) {
        guard let menuItem = menuItem else {
            Self.logger.warning("Keep Awake menu item outlet was nil")
            return
        }

        self.parentMenuItem = menuItem

        let submenu = menuItem.submenu ?? NSMenu(title: "Keep Awake")
        submenu.delegate = self
        menuItem.submenu = submenu
        self.submenu = submenu

        buildSubmenu(submenu)
        updateMenu()
        Self.logger.info("Keep Awake menu initialized from outlet")
    }

    @MainActor
    func updateMenu() {
        if let parent = parentMenuItem {
            if isActive {
                if let rem = formattedRemainingTime, rem != "Active" {
                    parent.title = "Keep Awake (\(rem))"
                } else {
                    parent.title = "Keep Awake (Active)"
                }
                parent.setImageIfDesired(systemSymbolName: "cup.and.saucer.fill")
            } else {
                parent.title = "Keep Awake (Caffeinate)"
                parent.setImageIfDesired(systemSymbolName: "cup.and.saucer")
            }
        }

        if let sub = submenu {
            buildSubmenu(sub)
        }
    }

    @MainActor
    private func buildSubmenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // Status Header Item
        let statusItem = NSMenuItem(title: detailedRemainingStatus, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(.separator())

        // Off
        let offItem = NSMenuItem(title: "Off", action: #selector(selectOff), keyEquivalent: "")
        offItem.target = self
        offItem.state = (activeDuration == .off) ? .on : .off
        offItem.setImageIfDesired(systemSymbolName: "powersleep")
        menu.addItem(offItem)

        // Indefinitely
        let indefItem = NSMenuItem(title: "Indefinitely", action: #selector(selectIndefinitely), keyEquivalent: "")
        indefItem.target = self
        indefItem.state = (activeDuration == .indefinitely) ? .on : .off
        indefItem.setImageIfDesired(systemSymbolName: "infinity")
        menu.addItem(indefItem)

        menu.addItem(.separator())

        // Durations: 1, 2, 5, 8 hours
        let hourOptions = [1, 2, 5, 8]
        for hours in hourOptions {
            let title = hours == 1 ? "For 1 Hour" : "For \(hours) Hours"
            let item = NSMenuItem(title: title, action: #selector(selectDurationItem(_:)), keyEquivalent: "")
            item.target = self
            item.tag = hours
            if case .hours(let activeHours) = activeDuration, activeHours == hours {
                item.state = .on
            } else {
                item.state = .off
            }
            item.setImageIfDesired(systemSymbolName: "clock")
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // Prevent Display Sleep toggle
        let displayItem = NSMenuItem(
            title: "Prevent Display Sleep",
            action: #selector(togglePreventDisplaySleepAction),
            keyEquivalent: ""
        )
        displayItem.target = self
        displayItem.state = preventDisplaySleep ? .on : .off
        displayItem.setImageIfDesired(systemSymbolName: "display")
        menu.addItem(displayItem)
    }

    // MARK: - Actions

    @MainActor
    @objc private func selectOff(_ sender: Any?) {
        activate(duration: .off)
    }

    @MainActor
    @objc private func selectIndefinitely(_ sender: Any?) {
        activate(duration: .indefinitely)
    }

    @MainActor
    @objc private func selectDurationItem(_ sender: NSMenuItem) {
        activate(duration: .hours(sender.tag))
    }

    @MainActor
    @objc private func togglePreventDisplaySleepAction(_ sender: Any?) {
        preventDisplaySleep.toggle()
    }
}

extension KeepAwakeManager: NSMenuDelegate {
    @MainActor
    func menuNeedsUpdate(_ menu: NSMenu) {
        buildSubmenu(menu)
    }
}
