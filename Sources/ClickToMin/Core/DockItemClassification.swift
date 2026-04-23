/// Pure-logic classification of Dock item AX roles and subroles.
///
/// Moved from `AXHitTester` so the filtering decisions are testable
/// without ApplicationServices or a live Dock process.
public enum DockItemClassification {
    /// Subroles that represent non-actionable Dock items (Finder, Trash,
    /// stacks, separators, minimized-window tiles). Clicks on these should
    /// not trigger a minimize.
    public static let excludedSubroles: Set<String> = [
        "AXSeparatorDockItem",
        "AXFolderDockItem",
        "AXTrashDockItem",
        "AXMinimizedWindowDockItem",
        "AXDesktopDockItem"
    ]

    /// Returns `true` if `role` identifies an AXDockItem element.
    public static func isDockItemRole(_ role: String?) -> Bool {
        role == "AXDockItem"
    }

    /// Returns `true` if `subrole` ends with "DockItem", covering
    /// Sonoma+ variants like "AXApplicationDockItem" that appear on
    /// nested wrapper elements.
    public static func isDockItemSubrole(_ subrole: String?) -> Bool {
        guard let subrole else { return false }
        return subrole.hasSuffix("DockItem")
    }

    /// Returns `true` if the given role or subrole identifies a Dock item.
    public static func isDockItem(role: String?, subrole: String?) -> Bool {
        isDockItemRole(role) || isDockItemSubrole(subrole)
    }

    /// Returns `true` if the subrole is a non-actionable Dock item type
    /// that should be filtered out of the click pipeline.
    public static func isExcluded(subrole: String?) -> Bool {
        guard let subrole else { return false }
        return excludedSubroles.contains(subrole)
    }
}
