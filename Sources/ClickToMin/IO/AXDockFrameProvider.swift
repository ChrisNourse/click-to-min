import AppKit
import ApplicationServices
import ClickToMinCore
import os.log

/// Queries the Dock's live accessibility frame and caches it for the
/// fast-path short-circuit in `DockGeometry.contains(_:)`.
///
/// Three observers keep the cache fresh:
///   1. Screen parameter changes (resolution / arrangement)
///   2. Dock relaunch
///   3. Dock preference changes (resize, move, auto-hide toggle)
///
/// Auto-hide handling: when auto-hide is enabled, the cached rect is
/// widened to a screen-edge strip along the Dock's configured edge so
/// the short-circuit still triggers while the Dock is revealed.
/// Fallback chain if 5pt proves too narrow: 5pt → 10pt → full-edge strip.
final class AXDockFrameProvider: NSObject, DockFrameProvider {
    // MARK: - Dependencies

    private let dockPID: () -> pid_t?

    // MARK: - Cached state

    private var cachedFrame: CGRect?

    // MARK: - Observer tokens

    private var screenObserver: NSObjectProtocol?
    private var launchObserver: NSObjectProtocol?
    // prefObserver uses target/selector (not block), so we don't store a
    // token — removeObserver(self) handles it in deinit.

    // MARK: - Init / Deinit

    /// - Parameter dockPIDProvider: Closure returning the Dock's PID.
    ///   Phase 3 wires this to `DockPIDCache.pid`.
    init(dockPIDProvider: @escaping () -> pid_t?) {
        self.dockPID = dockPIDProvider
        super.init()
        refreshFrame()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshFrame()
        }

        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.dock" else { return }
            self?.refreshFrame()
        }

        // DistributedNotificationCenter.addObserver(forName:object:queue:using:)
        // does not accept a suspension-behavior argument; use the
        // target/selector overload for that. Since prefchanged is rare and
        // we want immediate delivery, we use the selector form and post
        // a DispatchQueue.main.async inside the selector.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleDockPrefChanged(_:)),
            name: .init("com.apple.dock.prefchanged"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func handleDockPrefChanged(_ note: Notification) {
        // Dock prefs changed (resize, move, auto-hide toggle).
        // Dispatch to main to keep AX calls on the main thread.
        DispatchQueue.main.async { [weak self] in
            self?.refreshFrame()
        }
    }

    deinit {
        if let observer = screenObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - DockFrameProvider conformance

    /// Returns the cached Dock frame, widened for auto-hide if applicable.
    ///
    /// Near-miss re-query: if the cached frame is nil, attempts one
    /// re-query before returning nil. This catches cases where an
    /// observer notification was missed (e.g., distributed notification
    /// coalesced away).
    var frame: CGRect? {
        if cachedFrame == nil {
            refreshFrame()
        }
        return cachedFrame
    }

    // MARK: - Frame query

    private func refreshFrame() {
        guard let pid = dockPID() else {
            cachedFrame = nil
            return
        }

        let dockApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(dockApp, 0.25)

        let rawFrame = queryDockListFrame(dockApp: dockApp)
        cachedFrame = adjustForAutoHide(rawFrame)

        os_log("dock frame refreshed: %{public}@",
               log: Log.lifecycle, type: .info,
               cachedFrame.map { NSStringFromRect($0) } ?? "nil")
    }

    /// Finds the Dock's AXList element and returns its frame, or falls
    /// back to the union of individual AXDockItem frames.
    private func queryDockListFrame(dockApp: AXUIElement) -> CGRect? {
        // Walk the Dock app's children to find the AXList.
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockApp, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else {
            return nil
        }

        for child in children {
            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
                  let role = roleRef as? String, role == "AXList"
            else {
                continue
            }

            // Prefer the list element's own frame.
            if let listFrame = axFrame(of: child) {
                return listFrame
            }

            // Fallback: union of child item frames.
            var itemChildrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &itemChildrenRef) == .success,
                  let items = itemChildrenRef as? [AXUIElement]
            else {
                continue
            }

            var unionFrame: CGRect?
            for item in items {
                guard let itemFrame = axFrame(of: item) else { continue }
                unionFrame = unionFrame?.union(itemFrame) ?? itemFrame
            }
            return unionFrame
        }

        return nil
    }

    /// Reads kAXPositionAttribute + kAXSizeAttribute for an element.
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
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else {
            return nil
        }
        return CGRect(origin: point, size: size)
    }

    // MARK: - Auto-hide widening

    /// If the Dock is set to auto-hide, widens `rawFrame` to a screen-edge
    /// strip so the short-circuit still triggers while the Dock is being
    /// revealed by a mouse hover.
    ///
    /// Fallback chain (increase if 5pt proves too narrow in testing):
    ///   5pt → 10pt → full-edge strip along the Dock's configured edge.
    /// Full-edge strip widens the false-positive region slightly —
    /// acceptable since all it costs is one extra AX hit-test per edge
    /// click while the Dock is hidden.
    private func adjustForAutoHide(_ rawFrame: CGRect?) -> CGRect? {
        guard let raw = rawFrame else { return nil }

        let autoHide = CFPreferencesCopyAppValue(
            "autohide" as CFString,
            "com.apple.dock" as CFString
        ) as? Bool == true

        guard autoHide else { return raw }

        // Determine which edge the Dock is on.
        let orientation = dockOrientation()
        guard let screen = NSScreen.screens.first else { return raw }
        let screenFrame = screen.frame

        // 5pt screen-edge strip along the Dock's configured edge.
        // 5 → 10 → full-edge fallback chain — start at 5.
        let stripWidth: CGFloat = 5

        switch orientation {
        case .bottom:
            let minY = screenFrame.minY
            return CGRect(x: screenFrame.minX, y: minY,
                          width: screenFrame.width, height: stripWidth)
                .union(raw)
        case .left:
            let minX = screenFrame.minX
            return CGRect(x: minX, y: screenFrame.minY,
                          width: stripWidth, height: screenFrame.height)
                .union(raw)
        case .right:
            let maxX = screenFrame.maxX - stripWidth
            return CGRect(x: maxX, y: screenFrame.minY,
                          width: stripWidth, height: screenFrame.height)
                .union(raw)
        }
    }

    private enum DockOrientation {
        case bottom, left, right
    }

    private func dockOrientation() -> DockOrientation {
        guard let raw = CFPreferencesCopyAppValue(
            "orientation" as CFString,
            "com.apple.dock" as CFString
        ) as? String else {
            return .bottom
        }
        switch raw {
        case "left": return .left
        case "right": return .right
        default: return .bottom
        }
    }
}
