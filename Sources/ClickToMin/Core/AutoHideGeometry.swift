import CoreGraphics

/// Which screen edge the Dock occupies.
public enum DockOrientation: String {
    case bottom, left, right

    /// Parses the raw string from `com.apple.dock` preferences.
    /// Unknown or nil values default to `.bottom`.
    public init(rawPreference: String?) {
        switch rawPreference {
        case "left": self = .left
        case "right": self = .right
        default: self = .bottom
        }
    }
}

/// Widens `rawFrame` to include a screen-edge strip along the Dock's
/// configured edge, so the fast-path geometry check still triggers
/// while the Dock is revealed during auto-hide.
///
/// The strip is unioned with `rawFrame` so the result always covers
/// at least the original frame.
///
/// - Parameters:
///   - rawFrame: The Dock's AX frame before adjustment.
///   - orientation: Which screen edge the Dock occupies.
///   - screenFrame: The primary screen's frame.
///   - stripWidth: Width of the edge strip (default 5pt).
public func adjustFrameForAutoHide(
    rawFrame: CGRect,
    orientation: DockOrientation,
    screenFrame: CGRect,
    stripWidth: CGFloat = 5
) -> CGRect {
    switch orientation {
    case .bottom:
        CGRect(
            x: screenFrame.minX, y: screenFrame.minY,
            width: screenFrame.width, height: stripWidth
        ).union(rawFrame)
    case .left:
        CGRect(
            x: screenFrame.minX, y: screenFrame.minY,
            width: stripWidth, height: screenFrame.height
        ).union(rawFrame)
    case .right:
        CGRect(
            x: screenFrame.maxX - stripWidth, y: screenFrame.minY,
            width: stripWidth, height: screenFrame.height
        ).union(rawFrame)
    }
}
