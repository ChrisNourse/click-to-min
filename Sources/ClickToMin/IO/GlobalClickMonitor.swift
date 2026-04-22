import AppKit
import os.log

/// Wraps `NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown)`.
///
/// Install only after `AXIsProcessTrusted() == true`; the global
/// monitor yields no events without that grant — even if installed
/// first and the grant arrives later. Reinstall on re-grant.
///
/// Only `.leftMouseDown` is monitored. Right-click and Ctrl-click
/// intentionally excluded — they open the Dock context menu and must
/// not trigger a minimize.
///
/// Known caveats (not bugs):
/// - Does not fire for clicks on our own windows (moot — LSUIElement,
///   no windows).
/// - Does not fire while the screen is locked.
final class GlobalClickMonitor {

    private var monitor: Any?

    /// Begins monitoring global left-mouse-down events.
    ///
    /// Idempotent: calling `start()` while already monitoring is a no-op
    /// (guards against double-register via a stored monitor token).
    ///
    /// - Parameter onClick: Called on the main thread with the click's
    ///   screen location (NSEvent coordinate space — bottom-left origin).
    func start(onClick: @escaping (CGPoint) -> Void) {
        guard monitor == nil else { return }

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { event in
            onClick(event.locationInWindow)
        }

        os_log("global click monitor installed", log: Log.lifecycle, type: .info)
    }

    /// Removes the global event monitor. Safe to call when not monitoring.
    func stop() {
        guard let token = monitor else { return }
        NSEvent.removeMonitor(token)
        monitor = nil

        os_log("global click monitor torn down", log: Log.lifecycle, type: .info)
    }

    deinit {
        stop()
    }
}
