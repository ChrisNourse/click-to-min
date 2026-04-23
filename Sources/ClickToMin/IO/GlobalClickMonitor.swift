import AppKit
import CoreGraphics
import os.log

/// Global left-mouse-down listener implemented as a listen-only
/// `CGEventTap` at `.cgSessionEventTap`.
///
/// Historically this wrapped `NSEvent.addGlobalMonitorForEvents`, but
/// that API does not reliably fire for clicks on the Dock on macOS
/// Sonoma+ (the Dock consumes the event before the app-level monitor
/// sees it). A session event tap runs earlier in the event pipeline
/// and sees Dock clicks deterministically.
///
/// Install only after `AXIsProcessTrusted() == true`; creating a tap
/// without Accessibility permission returns nil. Reinstall on re-grant.
///
/// Only `.leftMouseDown` is observed. Right-click and Ctrl-click are
/// intentionally excluded — they open the Dock context menu and must
/// not trigger a minimize.
///
/// Listen-only: the callback returns the event unmodified, so clicks
/// propagate normally to the Dock.
final class GlobalClickMonitor {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var callback: ((CGPoint) -> Void)?

    /// Begins monitoring global left-mouse-down events.
    ///
    /// Idempotent: calling `start()` while already monitoring is a no-op.
    ///
    /// - Parameter onClick: Called on the main thread with the click's
    ///   screen location (NSEvent coordinate space — bottom-left origin,
    ///   converted from the CG top-left coordinates the tap delivers).
    func start(onClick: @escaping (CGPoint) -> Void) {
        guard tap == nil else { return }
        self.callback = onClick

        let mask: CGEventMask = 1 << CGEventType.leftMouseDown.rawValue

        // `userInfo` carries `self` into the C callback without retain cycles.
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<GlobalClickMonitor>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()
                monitor.handleTapEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            os_log("CGEventTap creation failed — Accessibility not granted?",
                   log: Log.lifecycle, type: .error)
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)

        self.tap = newTap
        self.runLoopSource = source

        os_log("global click monitor installed (CGEventTap)",
               log: Log.lifecycle, type: .info)
    }

    /// Removes the event tap. Safe to call when not monitoring.
    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        callback = nil

        os_log("global click monitor torn down", log: Log.lifecycle, type: .info)
    }

    deinit {
        stop()
    }

    // MARK: - Tap callback

    /// Called from the tap C trampoline. Re-enables the tap if the
    /// system disables it (timeout / user input), otherwise forwards
    /// the click location to `callback` on the main thread in NSEvent
    /// (bottom-left) coordinates.
    private func handleTapEvent(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .leftMouseDown else { return }

        // CGEvent location is top-left origin, anchored on the primary
        // display. Convert to NSEvent's bottom-left space using the
        // primary display height so downstream `CoordinateConverter`
        // sees the same coordinate space it got from NSEvent before.
        let cgPoint = event.location
        let primaryHeight = CGFloat(CGDisplayPixelsHigh(CGMainDisplayID()))
        let nsPoint = CGPoint(x: cgPoint.x, y: primaryHeight - cgPoint.y)

        let cb = callback
        DispatchQueue.main.async {
            cb?(nsPoint)
        }
    }
}
