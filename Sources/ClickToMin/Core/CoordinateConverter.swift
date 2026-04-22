import Foundation
import CoreGraphics

/// Converts NSEvent coordinates (bottom-left origin per screen) to
/// Accessibility coordinates (top-left origin, global coordinate space).
///
/// The global AX coordinate space places (0, 0) at the top-left of the
/// primary screen. Secondary screens extend in whatever direction they
/// are arranged (including negative x for screens left of primary, and
/// negative y for screens above primary).
///
/// NSEvent's `locationInWindow` for global monitors is in the screen's
/// own bottom-left coordinate system. The conversion is:
///
///     axY = screenFrame.maxY - (nsEventPoint.y - screenFrame.origin.y)
///
/// But since the global AX space has Y increasing downward from the
/// top of the primary screen, and NSScreen frames have Y increasing
/// upward from the bottom of the primary screen, the full formula
/// simplifies to finding which screen contains the point, then flipping
/// within the global coordinate space.
///
/// All values are in points (not pixels). Retina scaling is irrelevant
/// because both NSEvent and AX operate in points.
public struct CoordinateConverter {
    /// Screen frames in the NSScreen coordinate system (origin bottom-left
    /// of primary, Y increases upward). Injected so Core never reads
    /// NSScreen.screens.
    public let screenFrames: [CGRect]

    public init(screenFrames: [CGRect]) {
        self.screenFrames = screenFrames
    }

    /// Convert an NSEvent point (bottom-left origin, global screen coords)
    /// to AX top-left origin global coords.
    ///
    /// NSScreen and AX share the same X axis (left = 0, increases right).
    /// Only Y differs: NSScreen Y increases upward, AX Y increases downward.
    ///
    /// The primary screen always has origin (0, 0) in NSScreen coords.
    /// Its height defines the AX Y origin: AX (0, 0) = NSScreen (0, primaryHeight).
    ///
    /// Therefore: axY = primaryScreenHeight - nsEventY
    /// And: axX = nsEventX (unchanged)
    ///
    /// This works for all screens because NSScreen frames share the same
    /// global coordinate space — secondary screens have origins relative
    /// to the primary's (0, 0).
    public func toAX(_ nsEventPoint: CGPoint) -> CGPoint {
        // The primary screen is the one whose origin is (0, 0) in
        // NSScreen coordinates. If no screen has origin (0, 0) (shouldn't
        // happen), fall back to the tallest screen's maxY.
        let primaryMaxY: CGFloat
        if let primary = screenFrames.first(where: { $0.origin == .zero }) {
            primaryMaxY = primary.maxY
        } else if let tallest = screenFrames.max(by: { $0.maxY < $1.maxY }) {
            primaryMaxY = tallest.maxY
        } else {
            // No screens at all — identity transform as a safe fallback.
            return nsEventPoint
        }

        return CGPoint(x: nsEventPoint.x, y: primaryMaxY - nsEventPoint.y)
    }
}
