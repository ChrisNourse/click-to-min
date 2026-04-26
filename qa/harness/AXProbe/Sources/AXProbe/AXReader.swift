import AppKit
import ApplicationServices
import Foundation

// MARK: - AXReader protocol

/// Abstraction over the handful of AX/NSWorkspace queries the probe needs.
/// Real impl in `SystemAXReader`; test fakes live in AXProbeTests.
public protocol AXReader {
    func isProcessTrusted() -> Bool
    func frontmostBundleId() -> String?
    /// Returns `nil` if app isn't running, no focused window, or attribute missing.
    func focusedWindowMinimized(bundleId: String) -> Bool?
    /// Returns `true` if ANY window of the app is minimized. Use this for
    /// `wait-until-minimized`: after AXMinimize fires, the app often has no
    /// focused window so `focusedWindowMinimized` returns nil forever.
    func anyWindowMinimized(bundleId: String) -> Bool?
    func windowCount(bundleId: String) -> Int?
    /// Returns the AX frame of the Dock tile whose URL matches the given bundle id.
    func dockItemFrame(bundleId: String) -> CGRect?
}

// MARK: - SystemAXReader (real)

final class SystemAXReader: AXReader {
    func isProcessTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func frontmostBundleId() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func focusedWindowMinimized(bundleId: String) -> Bool? {
        guard let app = runningApp(bundleId: bundleId) else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowRef
        ) == .success, let windowRefUnwrapped = windowRef else {
            return nil
        }
        // AXUIElement is a CF type; force cast is API-contract safe.
        // swiftlint:disable:next force_cast
        let window = windowRefUnwrapped as! AXUIElement
        var minRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            &minRef
        ) == .success else {
            return nil
        }
        // CFBoolean -> Bool.
        return (minRef as? Bool) ?? false
    }

    func windowCount(bundleId: String) -> Int? {
        guard let app = runningApp(bundleId: bundleId) else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        ) == .success, let windows = windowsRef as? [AXUIElement] else {
            return nil
        }
        return windows.count
    }

    func anyWindowMinimized(bundleId: String) -> Bool? {
        guard let app = runningApp(bundleId: bundleId) else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        ) == .success, let windows = windowsRef as? [AXUIElement] else {
            return nil
        }
        for window in windows {
            var minRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                window,
                kAXMinimizedAttribute as CFString,
                &minRef
            ) == .success else { continue }
            if (minRef as? Bool) == true { return true }
        }
        return false
    }

    func dockItemFrame(bundleId: String) -> CGRect? {
        guard let dock = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.dock"
        }) else { return nil }
        let dockApp = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(dockApp, 0.5)

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            dockApp,
            kAXChildrenAttribute as CFString,
            &childrenRef
        ) == .success, let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        for child in children {
            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                child,
                kAXRoleAttribute as CFString,
                &roleRef
            ) == .success, (roleRef as? String) == "AXList" else {
                continue
            }
            var itemsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                child,
                kAXChildrenAttribute as CFString,
                &itemsRef
            ) == .success, let items = itemsRef as? [AXUIElement] else {
                continue
            }
            for item in items {
                guard let itemBundle = dockItemBundleId(item),
                      itemBundle == bundleId else { continue }
                return axFrame(of: item)
            }
        }
        return nil
    }

    // MARK: - helpers

    private func runningApp(bundleId: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleId }
    }

    private func dockItemBundleId(_ element: AXUIElement) -> String? {
        var urlRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXURLAttribute as CFString,
            &urlRef
        ) == .success else { return nil }
        // CFURL -> URL.
        // swiftlint:disable:next force_cast
        let url = urlRef as! CFURL as URL
        return Bundle(url: url)?.bundleIdentifier
    }

    private func axFrame(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success
        else {
            return nil
        }
        var point = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable force_cast
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else {
            return nil
        }
        // swiftlint:enable force_cast
        return CGRect(origin: point, size: size)
    }
}
