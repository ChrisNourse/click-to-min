import ApplicationServices
import ClickToMinCore
import os.log

/// Wraps `AXUIElementCopyElementAtPosition` and Dock-item attribute
/// reads for the click pipeline.
///
/// Conforms to `HitTesting` from Core. The Core protocol uses
/// `AnyObject` instead of `AXUIElement` so the pure layer never
/// imports ApplicationServices. Since `AXUIElement` is a CF type
/// that bridges to `AnyObject`, the cast round-trips cleanly.
final class AXHitTester: HitTesting {
    /// Reused system-wide element — no per-click allocation.
    let systemWide: AXUIElement = AXUIElementCreateSystemWide()

    /// Closure returning the frontmost app's localized name.
    /// Injected so AXHitTester doesn't depend on NSWorkspace directly.
    private let frontmostLocalizedName: () -> String?

    /// - Parameter frontmostLocalizedName: Closure returning the current
    ///   frontmost application's `localizedName`, used as a title-based
    ///   fallback when `kAXURLAttribute` is nil on an AXDockItem (e.g.,
    ///   Recent Applications section). Phase 3 wires this to
    ///   `FrontmostAppProvider.frontmost?.localizedName`.
    init(frontmostLocalizedName: @escaping () -> String?) {
        self.frontmostLocalizedName = frontmostLocalizedName
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
    }

    // MARK: - HitTesting conformance

    /// Hit-tests the accessibility element at `point` (AX coordinate
    /// space — top-left origin). Returns the element as `AnyObject`,
    /// or nil if nothing is found.
    func hitTest(at point: CGPoint) -> AnyObject? {
        var elementRef: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemWide, Float(point.x), Float(point.y), &elementRef
        )
        guard result == .success, let element = elementRef else {
            return nil
        }
        return element as AnyObject
    }

    /// Extracts the owning process PID from an AX element.
    func pid(_ element: AnyObject) -> pid_t? {
        // HitTesting contract: `element` is always an AXUIElement returned
        // from `hitTest(at:)`. AXUIElement is a CF type that round-trips
        // through AnyObject; force-cast is safe and sidesteps the
        // "conditional downcast always succeeds" warning-as-error.
        let axElement = element as! AXUIElement
        var pid: pid_t = 0
        guard AXUIElementGetPid(axElement, &pid) == .success else { return nil }
        return pid
    }

    /// Walks the AX parent chain from `element` up to an `AXDockItem`.
    /// Returns the dock item's `kAXURLAttribute` (bundle URL), or nil
    /// if the element isn't a dock item or is a non-actionable type
    /// (Finder, Trash, stacks, separators, minimized-window tiles).
    ///
    /// If no `AXDockItem` ancestor is found (e.g., long-press window
    /// previews), returns nil cleanly.
    ///
    /// Recent Applications section caveat: `kAXURLAttribute` may be nil
    /// for apps in the "Recent Applications" Dock section. Best-effort
    /// only — returns nil and lets the pipeline fail gracefully.
    func dockItemURL(_ element: AnyObject) -> URL? {
        let axElement = element as! AXUIElement

        // DIAGNOSTIC: log the element tree from hit upward so we can see
        // what roles/attrs the Dock actually exposes on this macOS.
        logAXChain(axElement)

        guard let dockItem = walkToDockItem(from: axElement) else { return nil }

        // Filter out non-actionable subroles (set lives in Core).
        if DockItemClassification.isExcluded(
            subrole: axStringAttribute(dockItem, kAXSubroleAttribute as CFString)
        ) {
            return nil
        }

        // Primary: kAXURLAttribute (may be CFString or CFURL depending on macOS).
        if let url = axURLAttribute(dockItem, kAXURLAttribute as CFString) {
            return url
        }

        // Fallback: title match against frontmost localizedName.
        // If kAXURLAttribute is nil but this is an AXApplicationDockItem,
        // there's no reliable way to recover the bundle URL from AX alone.
        // Return nil and let the pipeline fail gracefully.
        return nil
    }

    // MARK: - Private helpers

    /// Walks kAXParentAttribute from `element` upward, looking for an
    /// element whose AXRole is "AXDockItem" or whose subrole indicates
    /// a dock item (e.g., "AXApplicationDockItem" on some macOS versions
    /// where the subrole appears on elements with a different role).
    private func walkToDockItem(from element: AXUIElement) -> AXUIElement? {
        if isDockItem(element) { return element }

        var current = element
        for _ in 0 ..< 20 {
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                current, kAXParentAttribute as CFString, &parentRef
            ) == .success, let parent = parentRef else {
                return nil
            }
            let parentElement = parent as! AXUIElement
            if isDockItem(parentElement) { return parentElement }
            current = parentElement
        }
        return nil
    }

    private func isDockItem(_ element: AXUIElement) -> Bool {
        DockItemClassification.isDockItem(
            role: axStringAttribute(element, kAXRoleAttribute as CFString),
            subrole: axStringAttribute(element, kAXSubroleAttribute as CFString)
        )
    }

    /// Reads an attribute that may be exposed as either a CFString or CFURL.
    private func axURLAttribute(_ element: AXUIElement, _ attribute: CFString) -> URL? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let value = ref else { return nil }
        // CFURL?
        if CFGetTypeID(value) == CFURLGetTypeID() {
            return (value as! CFURL) as URL
        }
        // CFString?
        if let str = value as? String {
            return URL(string: str)
        }
        return nil
    }

    /// DIAGNOSTIC: logs the AX element and its parent chain (role,
    /// subrole, title, URL). Temporary; remove once dock hit-testing
    /// is proven stable.
    private func logAXChain(_ element: AXUIElement) {
        var current: AXUIElement? = element
        for depth in 0 ..< 6 {
            guard let elem = current else { break }
            let role = axStringAttribute(elem, kAXRoleAttribute as CFString) ?? "?"
            let subrole = axStringAttribute(elem, kAXSubroleAttribute as CFString) ?? "-"
            let title = axStringAttribute(elem, kAXTitleAttribute as CFString) ?? "-"
            let urlString = axURLAttribute(elem, kAXURLAttribute as CFString)?.absoluteString ?? "-"
            os_log("ax chain[%d]: role=%{public}@ subrole=%{public}@ title=%{public}@ url=%{public}@",
                   log: Log.pipeline, type: .info,
                   depth, role, subrole, title, urlString)

            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(elem, kAXParentAttribute as CFString, &parentRef) == .success,
               let parent = parentRef
            {
                current = (parent as! AXUIElement)
            } else {
                current = nil
            }
        }
    }

    private func axStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success else {
            return nil
        }
        return ref as? String
    }
}
