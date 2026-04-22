import Foundation
import CoreGraphics

/// Abstracts the live Dock frame so `DockGeometry` stays pure and testable.
/// Implemented by `AXDockFrameProvider` in the I/O layer.
public protocol DockFrameProvider: AnyObject {
    var frame: CGRect? { get }
}

/// Fast-path check: does a click point fall inside the cached Dock region?
/// Eliminates AX IPC on ~99% of clicks (those outside the Dock).
///
/// Uses the provider's current frame on each call so frame changes
/// (Dock resize, move, auto-hide toggle) propagate immediately.
public struct DockGeometry {
    public let provider: DockFrameProvider

    public init(provider: DockFrameProvider) {
        self.provider = provider
    }

    /// Returns `true` if `point` is inside or on the edge of the Dock
    /// frame. Returns `false` if the provider's frame is nil (Dock
    /// mid-relaunch, frame unknown) — the click falls through and AX
    /// will bail on its own.
    public func contains(_ point: CGPoint) -> Bool {
        guard let frame = provider.frame else { return false }
        // CGRect.contains returns true for points strictly inside and on
        // the minX/minY edges, but false for maxX/maxY edges. We want
        // "on edge" to count as inside for all four edges.
        return point.x >= frame.minX
            && point.x <= frame.maxX
            && point.y >= frame.minY
            && point.y <= frame.maxY
    }
}
