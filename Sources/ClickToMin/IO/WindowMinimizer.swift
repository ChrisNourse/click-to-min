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
///
/// Restore detection: if the focused window is already minimized at
/// click time, the click is a *restore*, not a minimize. We skip the
/// schedule entirely; otherwise we'd fight the Dock's un-minimize and
/// cause a visible flash-then-reminimize.
final class WindowMinimizer: WindowMinimizing {
    /// Delay applied before the AX minimize set. Empirically 180ms is
    /// enough to let the Dock finish its click handling on Sonoma+
    /// while still feeling snappy.
    static let postClickDelay: TimeInterval = 0.18

    /// Minimizes the focused window of the process identified by `pid`,
    /// after a brief delay to let the Dock finish its own click handling.
    ///
    /// No-op (with log) if the focused window is already minimized —
    /// the click is a restore, not a minimize.
    ///
    /// - Parameters:
    ///   - pid: The target process identifier.
    ///   - bundleURL: Passed through for logging only; unused for the
    ///     AX call itself.
    func minimizeFocusedWindow(ofPid pid: pid_t, bundleURL _: URL?) {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.25)

        guard let focusedWindow = copyFocusedWindow(of: appElement) else {
            os_log("pipeline: no focused window for pid %d at click time, no-op",
                   log: Log.pipeline, type: .info, pid)
            return
        }

        if isMinimized(focusedWindow) {
            os_log("pipeline: focused window already minimized for pid %d — restore, no-op",
                   log: Log.pipeline, type: .info, pid)
            return
        }

        os_log("pipeline: minimize scheduled for pid %d (delay %{public}.2fs)",
               log: Log.pipeline, type: .info, pid, Self.postClickDelay)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.postClickDelay) {
            self.performMinimize(pid: pid, window: focusedWindow)
        }
    }

    // MARK: - Private

    private func performMinimize(pid: pid_t, window: AXUIElement) {
        AXUIElementSetAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            kCFBooleanTrue
        )

        os_log("pipeline: minimize dispatched for pid %d",
               log: Log.pipeline, type: .info, pid)
    }

    private func copyFocusedWindow(of appElement: AXUIElement) -> AXUIElement? {
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &windowRef
        ) == .success, let window = windowRef else { return nil }
        return (window as! AXUIElement)
    }

    private func isMinimized(_ window: AXUIElement) -> Bool {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window, kAXMinimizedAttribute as CFString, &valueRef
        ) == .success, let value = valueRef else { return false }
        return CFBooleanGetValue((value as! CFBoolean))
    }
}
