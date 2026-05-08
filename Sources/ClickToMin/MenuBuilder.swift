import AppKit
import ClickToMinCore

enum MenuBuilder {
    struct State {
        var missingPermission: Bool
        var enabled: Bool
        var iconHidden: Bool
        var version: String
    }

    static func buildMenu(state: State, target: AnyObject) -> NSMenu {
        let menu = NSMenu()

        let statusItem: NSMenuItem
        if state.missingPermission {
            statusItem = NSMenuItem(
                title: "Needs Accessibility Permission\u{2026}",
                action: #selector(AppDelegate.openAccessibilitySettingsMenuAction),
                keyEquivalent: ""
            )
            statusItem.target = target
            statusItem.image = NSImage(
                systemSymbolName: "circle.fill",
                accessibilityDescription: "Permission required"
            )?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            )
            statusItem.toolTip = "Click to open System Settings \u{2192} Privacy & Security \u{2192} Accessibility"
        } else {
            statusItem = NSMenuItem(
                title: "Ready",
                action: nil,
                keyEquivalent: ""
            )
            statusItem.image = NSImage(
                systemSymbolName: "checkmark.circle.fill",
                accessibilityDescription: "Permission granted"
            )?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [.systemGreen])
            )
        }
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        let enableItem = NSMenuItem(
            title: "Enable ClickToMin",
            action: #selector(AppDelegate.toggleEnabled(_:)),
            keyEquivalent: ""
        )
        enableItem.target = target
        enableItem.state = state.enabled ? .on : .off
        menu.addItem(enableItem)

        let showItem = NSMenuItem(
            title: "Show in menu bar",
            action: #selector(AppDelegate.toggleIconVisibility(_:)),
            keyEquivalent: ""
        )
        showItem.target = target
        showItem.state = state.iconHidden ? .off : .on
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(
            title: "About ClickToMin v\(state.version)",
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(aboutItem)

        menu.addItem(
            withTitle: "Quit ClickToMin",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )

        return menu
    }
}
