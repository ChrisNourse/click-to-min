import AppKit
import ClickToMinCore

enum MenuBuilder {
    struct State {
        var missingPermission: Bool
        var enabled: Bool
        var iconHidden: Bool
    }

    static func buildMenu(state: State, target: AnyObject) -> NSMenu {
        let menu = NSMenu()

        menu.addItem(statusMenuItem(missingPermission: state.missingPermission, target: target))

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
            title: "About ClickToMin",
            action: #selector(AppDelegate.showAboutPanel),
            keyEquivalent: ""
        )
        aboutItem.target = target
        menu.addItem(aboutItem)

        menu.addItem(
            withTitle: "Quit ClickToMin",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )

        return menu
    }

    private static func statusMenuItem(missingPermission: Bool, target: AnyObject) -> NSMenuItem {
        if missingPermission {
            let item = NSMenuItem(
                title: "Needs Accessibility Permission\u{2026}",
                action: #selector(AppDelegate.openAccessibilitySettingsMenuAction),
                keyEquivalent: ""
            )
            item.target = target
            item.image = NSImage(
                systemSymbolName: "circle.fill",
                accessibilityDescription: "Permission required"
            )?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            )
            item.toolTip = "Click to open System Settings \u{2192} Privacy & Security \u{2192} Accessibility"
            return item
        }
        let item = NSMenuItem(
            title: "Ready",
            action: nil,
            keyEquivalent: ""
        )
        item.image = NSImage(
            systemSymbolName: "checkmark.circle.fill",
            accessibilityDescription: "Permission granted"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(paletteColors: [.systemGreen])
        )
        return item
    }
}
