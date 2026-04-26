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
    private var pollTimer: Timer?

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

        // Poll fallback: some Dock restarts (notably those triggered by
        // toggling `autohide`) do not deliver `didLaunchApplicationNotification`
        // reliably. A 2s NSRunningApplication re-query catches those cases
        // so click validation doesn't silently use a dead Dock PID.
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshIfChanged()
        }
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    deinit {
        if let observer = launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        pollTimer?.invalidate()
    }

    // MARK: - Private

    /// Queries `NSRunningApplication.runningApplications` for the Dock.
    /// Tie-break logic lives in `selectBestDockProcess` (Core).
    private func refresh() {
        let candidates = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.dockBundleID
        ).map {
            DockProcessCandidate(
                processIdentifier: $0.processIdentifier,
                isTerminated: $0.isTerminated,
                launchDate: $0.launchDate
            )
        }

        pid = selectBestDockProcess(candidates)

        os_log("dock PID refreshed: %{public}d",
               log: Log.lifecycle, type: .info,
               pid.map { Int32($0) } ?? -1)
    }

    /// Refresh only if the live Dock PID differs from cached, to keep the
    /// log quiet. Called by the 2s poll fallback.
    private func refreshIfChanged() {
        let candidates = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.dockBundleID
        ).map {
            DockProcessCandidate(
                processIdentifier: $0.processIdentifier,
                isTerminated: $0.isTerminated,
                launchDate: $0.launchDate
            )
        }
        let live = selectBestDockProcess(candidates)
        if live != pid {
            pid = live
            os_log("dock PID refreshed (poll): %{public}d",
                   log: Log.lifecycle, type: .info,
                   live.map { Int32($0) } ?? -1)
        }
    }
}
