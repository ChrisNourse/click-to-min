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

    // MARK: - Stored properties

    private var statusItem: NSStatusItem?
    private var dockWatcher: DockWatcher?
    private var permissionTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    /// Track whether we've already shown the permission alert this launch,
    /// so we don't spam the user on every 2s poll.
    private var hasShownPermissionAlert = false

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Redundant with LSUIElement=YES in Info.plist, but covers
        // unbundled launches via `swift run` where LSUIElement doesn't
        // take effect.
        NSApp.setActivationPolicy(.accessory)

        installStatusItem()

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
        if let t = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(t)
        }
    }

    // MARK: - Status bar

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            if let url = Bundle.main.url(forResource: "menubar-icon", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                image.isTemplate = true
                button.image = image
            } else {
                // Fallback for unbundled `swift run` launches.
                button.image = NSImage(
                    systemSymbolName: "arrow.down.to.line",
                    accessibilityDescription: "ClickToMin"
                )
            }
        }

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Quit ClickToMin",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        statusItem?.menu = menu
    }

    // MARK: - Permission lifecycle

    private func checkPermissionAndMaybeStart() {
        if AXIsProcessTrusted() {
            // Permission granted.
            permissionTimer?.invalidate()
            permissionTimer = nil

            if dockWatcher == nil {
                dockWatcher = DockWatcher()
                dockWatcher?.start()
                os_log("permission granted, DockWatcher installed",
                       log: Log.lifecycle, type: .info)
            }
        } else {
            // Permission missing or revoked.
            dockWatcher?.stop()
            dockWatcher = nil

            if permissionTimer == nil {
                // Show alert only the first time we discover missing permission.
                if !hasShownPermissionAlert {
                    hasShownPermissionAlert = true
                    showPermissionAlert()
                    openAccessibilitySettings()
                }

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

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        ClickToMin needs Accessibility permission to detect Dock clicks \
        and minimize windows. Please grant access in System Settings, \
        then the app will activate automatically.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
