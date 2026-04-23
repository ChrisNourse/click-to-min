import CoreGraphics
import Foundation

// MARK: - Test-facing protocols for DockWatcher pipeline

//
// These live in ClickToMinCore so the coordinator (Phase 3) can be
// tested with in-memory fakes that don't require AppKit, AX, or a
// live user session.
//
// The AX element type is `AnyObject` (not `AXUIElement`) so Core
// never needs to import ApplicationServices.

/// Hit-tests the accessibility element at a screen point and extracts
/// PID / Dock-item URL from the result.
public protocol HitTesting {
    func hitTest(at point: CGPoint) -> AnyObject?
    func pid(_ element: AnyObject) -> pid_t?
    func dockItemURL(_ element: AnyObject) -> URL?
}

/// Provides the cached Dock process identifier for O(1) per-click
/// PID validation.
public protocol DockPIDProviding {
    var pid: pid_t? { get }
}

/// Minimizes the focused window of the process identified by `pid`.
/// `bundleURL` is passed through for logging / diagnostics only.
public protocol WindowMinimizing {
    func minimizeFocusedWindow(ofPid pid: pid_t, bundleURL: URL?)
}

/// Returns the frontmost application's PID and bundle URL.
/// Decoupled from `NSRunningApplication` so Core stays pure.
public protocol FrontmostAppInfoProviding {
    var frontmostPidAndURL: (pid: pid_t, bundleURL: URL?)? { get }
}
