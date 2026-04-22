import AppKit
import ClickToMinCore

/// Abstracts the frontmost application so `DockWatcher` and pipeline
/// tests can substitute an in-memory fake without subclassing NSWorkspace.
///
/// Protocol pair exists so `DockWatcherPipelineTests` can fake frontmost
/// flipping between pipeline stages (e.g., frontmost changes between
/// the hit-test and the minimize-dispatch).
public protocol FrontmostAppProviding {
    var frontmost: NSRunningApplication? { get }
}

/// Live implementation — reads `NSWorkspace.shared.frontmostApplication`
/// on every access. No caching; the coordinator reads at click-dispatch
/// time per PLAN.md §Coordinator.
public struct FrontmostAppProvider: FrontmostAppProviding {

    public init() {}

    public var frontmost: NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }
}

// MARK: - Core protocol conformance

/// Bridges `FrontmostAppProvider` to the pure `FrontmostAppInfoProviding`
/// protocol from ClickToMinCore (which can't reference NSRunningApplication).
extension FrontmostAppProvider: FrontmostAppInfoProviding {

    public var frontmostPidAndURL: (pid: pid_t, bundleURL: URL?)? {
        guard let app = frontmost else { return nil }
        return (app.processIdentifier, app.bundleURL)
    }
}
