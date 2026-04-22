import ApplicationServices
import ClickToMinCore
import os.log

/// Minimizes the focused window of a given process via Accessibility.
///
/// `kAXMinimizedAttribute` set is asynchronous — the call returns before
/// the window animates. Do not assert visual state from this call.
final class WindowMinimizer: WindowMinimizing {

    /// Minimizes the focused window of the process identified by `pid`.
    ///
    /// - Parameters:
    ///   - pid: The target process identifier.
    ///   - bundleURL: Passed through for logging only; unused for the
    ///     AX call itself.
    func minimizeFocusedWindow(ofPid pid: pid_t, bundleURL: URL?) {
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

        // window is an AXUIElement (CF type).
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
