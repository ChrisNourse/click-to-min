import AppKit
import ApplicationServices
import ClickToMinCore
import os.log

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    private var statusItem: NSStatusItem?
    private var dockWatcher: DockWatcher?
    private var permissionTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var reopenObserver: NSObjectProtocol?
    private let settings: UserDefaultsSettings = UserDefaultsSettings()

    private var statusReflectsMissingPermission = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isDuplicateInstance() {
            DistributedNotificationCenter.default().postNotificationName(
                .clickToMinReopen,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return
        }

        NSApp.setActivationPolicy(.accessory)

        installStatusItem()
        observeSettings()
        observeReopenNotification()

        checkPermissionAndMaybeStart()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkPermissionAndMaybeStart()
        }

        os_log("app launched", log: Log.lifecycle, type: .info)
    }

    func applicationWillTerminate(_ notification: Notification) {
        dockWatcher?.stop()
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = reopenObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if settings.iconHidden {
            settings.iconHidden = false
        }
        return false
    }

    // MARK: - Status bar

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        installStatusItemIcon()
        rebuildMenu()
    }

    private func installStatusItemIcon() {
        guard let button = statusItem?.button else { return }
        if let url = Bundle.main.url(forResource: "menubar-icon", withExtension: "png"),
           let image = NSImage(contentsOf: url)
        {
            image.isTemplate = true
            button.image = image
        } else {
            button.image = NSImage(
                systemSymbolName: "arrow.down.to.line",
                accessibilityDescription: "ClickToMin"
            )
        }
    }

    private func rebuildMenu() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let state = MenuBuilder.State(
            missingPermission: !AXIsProcessTrusted(),
            enabled: settings.enabled,
            iconHidden: settings.iconHidden,
            version: version
        )
        statusItem?.menu = MenuBuilder.buildMenu(state: state, target: self)
    }

    // MARK: - Menu actions

    @objc func openAccessibilitySettingsMenuAction() {
        openAccessibilitySettings()
    }

    @objc func toggleEnabled(_ sender: NSMenuItem) {
        settings.enabled.toggle()
    }

    @objc func toggleIconVisibility(_ sender: NSMenuItem) {
        if !settings.iconHidden {
            let acknowledged = UserDefaults.standard.bool(forKey: SettingsKeys.hideAcknowledged)
            if !acknowledged {
                let alert = NSAlert()
                alert.messageText = "Hide menu bar icon?"
                alert.informativeText = "You can re-show the icon by launching ClickToMin from Applications."
                alert.addButton(withTitle: "Hide")
                alert.addButton(withTitle: "Cancel")
                let response = alert.runModal()
                guard response == .alertFirstButtonReturn else { return }
                UserDefaults.standard.set(true, forKey: SettingsKeys.hideAcknowledged)
            }
        }
        settings.iconHidden.toggle()
    }

    // MARK: - Settings observation

    private func observeSettings() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsChanged,
            object: settings,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.applySettings()
            self.rebuildMenu()
        }
    }

    private func applySettings() {
        if settings.enabled {
            if dockWatcher != nil, AXIsProcessTrusted() {
                dockWatcher?.start()
            }
        } else {
            dockWatcher?.stop()
        }

        statusItem?.isVisible = !settings.iconHidden
    }

    // MARK: - Reopen notification (duplicate-instance handoff)

    private func observeReopenNotification() {
        reopenObserver = DistributedNotificationCenter.default().addObserver(
            forName: .clickToMinReopen,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.settings.iconHidden {
                self.settings.iconHidden = false
            }
        }
    }

    private func isDuplicateInstance() -> Bool {
        let apps = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        )
        return apps.count > 1
    }

    // MARK: - Permission lifecycle

    private func checkPermissionAndMaybeStart() {
        if AXIsProcessTrusted() {
            permissionTimer?.invalidate()
            permissionTimer = nil

            if statusReflectsMissingPermission {
                statusReflectsMissingPermission = false
                rebuildMenu()
            }

            if dockWatcher == nil {
                dockWatcher = DockWatcher()
                if settings.enabled {
                    dockWatcher?.start()
                }
                os_log("permission granted, DockWatcher installed",
                       log: Log.lifecycle, type: .info)
            }
        } else {
            dockWatcher?.stop()
            dockWatcher = nil

            if !statusReflectsMissingPermission {
                statusReflectsMissingPermission = true
                rebuildMenu()
            }

            if permissionTimer == nil {
                permissionTimer = Timer.scheduledTimer(
                    withTimeInterval: 2.0,
                    repeats: true
                ) { [weak self] _ in
                    self?.checkPermissionAndMaybeStart()
                }

                os_log("permission missing, polling started",
                       log: Log.lifecycle, type: .info)
            }
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension Notification.Name {
    static let clickToMinReopen = Notification.Name("com.click-to-min.reopen")
}
