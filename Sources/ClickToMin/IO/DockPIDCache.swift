import AppKit
import ClickToMinCore
import os.log

/// Caches the Dock process identifier for O(1) per-click PID validation.
///
/// Populates on init; refreshes on `NSWorkspace.didLaunchApplicationNotification`
/// filtered to `com.apple.dock`. A brief window where the cache points at
/// a dying Dock PID after a Dock restart is acceptable — the PID check
/// simply fails for one click.
final class DockPIDCache: DockPIDProviding {
    /// O(1) stored read.
    private(set) var pid: pid_t?

    private var launchObserver: NSObjectProtocol?

    private static let dockBundleID = "com.apple.dock"

    init() {
        refresh()

        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Self.dockBundleID else { return }
            self?.refresh()
        }
    }

    deinit {
        if let t = launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(t)
        }
    }

    // MARK: - Private

    /// Queries `NSRunningApplication.runningApplications` for the Dock.
    ///
    /// Multi-match tie-break (during Dock relaunch, both old and new
    /// instances can appear transiently):
    ///   1. Never cache a terminated instance.
    ///   2. Prefer the instance with the latest `launchDate`.
    ///   3. If `launchDate` is nil for one, prefer the non-nil.
    private func refresh() {
        let candidates = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.dockBundleID
        ).filter { !$0.isTerminated }

        let best = candidates.max { a, b in
            switch (a.launchDate, b.launchDate) {
            case (nil, .some):
                true // prefer b (non-nil date)
            case (.some, nil):
                false // prefer a (non-nil date)
            case let (.some(da), .some(db)):
                da < db // prefer later date
            case (nil, nil):
                false // arbitrary stable order
            }
        }

        pid = best?.processIdentifier

        os_log("dock PID refreshed: %{public}d",
               log: Log.lifecycle, type: .info,
               pid.map { Int32($0) } ?? -1)
    }
}
