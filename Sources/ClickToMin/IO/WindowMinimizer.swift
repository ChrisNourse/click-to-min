import ApplicationServices
import ClickToMinCore
import Foundation
import os.log

/// Minimizes the focused window of a given process via Accessibility.
///
/// `kAXMinimizedAttribute` set is asynchronous — the call returns before
/// the window animates. Do not assert visual state from this call.
///
/// The actual AX set is deferred by `postClickDelay` so the Dock's own
/// click handling (which can re-activate/un-minimize the target app)
/// runs first. Without this delay, clicking a frontmost app's Dock
/// tile triggers a minimize → Dock un-minimize race, and the Dock wins.
final class WindowMinimizer: WindowMinimizing {
    /// Delay applied before the AX minimize set. Empirically 300ms is
    /// enough to let the Dock finish its click handling on Sonoma+.
    static let postClickDelay: TimeInterval = 0.30

    /// Minimizes the focused window of the process identified by `pid`,
    /// after a brief delay to let the Dock finish its own click handling.
    ///
    /// - Parameters:
    ///   - pid: The target process identifier.
    ///   - bundleURL: Passed through for logging only; unused for the
    ///     AX call itself.
    func minimizeFocusedWindow(ofPid pid: pid_t, bundleURL _: URL?) {
        os_log("pipeline: minimize scheduled for pid %d (delay %{public}.2fs)",
               log: Log.pipeline, type: .info, pid, Self.postClickDelay)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.postClickDelay) {
            self.performMinimize(pid: pid)
        }
    }

    private func performMinimize(pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.25)

        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &windowRef
        ) == .success, let window = windowRef else {
            os_log("pipeline: no focused window for pid %d, no-op",
                   log: Log.pipeline, type: .info, pid)
            return
        }

        let windowElement = window as! AXUIElement
        AXUIElementSetAttributeValue(
            windowElement,
            kAXMinimizedAttribute as CFString,
            kCFBooleanTrue
        )

        os_log("pipeline: minimize dispatched for pid %d",
               log: Log.pipeline, type: .info, pid)
    }
}
