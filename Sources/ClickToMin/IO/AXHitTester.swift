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
        guard let dockItem = walkToDockItem(from: axElement) else { return nil }

        // Filter out non-actionable subroles.
        if let subrole = axStringAttribute(dockItem, kAXSubroleAttribute as CFString) {
            let excluded: Set<String> = [
                "AXSeparatorDockItem",
                "AXFolderDockItem",
                "AXTrashDockItem",
                "AXMinimizedWindowDockItem",
                "AXDesktopDockItem",
            ]
            if excluded.contains(subrole) {
                return nil
            }
        }

        // Primary: kAXURLAttribute
        if let urlString = axStringAttribute(dockItem, kAXURLAttribute as CFString),
           let url = URL(string: urlString) {
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
    /// element whose AXRole is "AXDockItem". Returns nil if none found
    /// (e.g., long-press preview children that aren't inside a dock item).
    private func walkToDockItem(from element: AXUIElement) -> AXUIElement? {
        var current = element

        // Check the element itself first.
        if axStringAttribute(current, kAXRoleAttribute as CFString) == "AXDockItem" {
            return current
        }

        // Walk up. Limit iterations to avoid infinite loops on malformed
        // hierarchies.
        for _ in 0..<20 {
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                current, kAXParentAttribute as CFString, &parentRef
            ) == .success, let parent = parentRef else {
                return nil
            }
            // parentRef is an AXUIElement (CF type).
            let parentElement = parent as! AXUIElement
            if axStringAttribute(parentElement, kAXRoleAttribute as CFString) == "AXDockItem" {
                return parentElement
            }
            current = parentElement
        }

        return nil
    }

    private func axStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success else {
            return nil
        }
        return ref as? String
    }
}
