// Coordinator. Wires Core + I/O; real logic lives in runClickPipeline.
// All AX calls on main thread (AX thread affinity).

import AppKit
import ApplicationServices
import ClickToMinCore
import os.log

/// Coordinator that holds all concrete I/O adapter instances and wires
/// them into `runClickPipeline` on each global left-click.
///
/// No branching logic of its own — the pipeline is the only thing here.
/// `start()` / `stop()` let `AppDelegate` re-grant / revoke cleanly.
final class DockWatcher {
    // MARK: - I/O adapters (strong refs kept alive for app lifetime)

    private let clickMonitor = GlobalClickMonitor()
    private let dockPIDCache = DockPIDCache()
    private let hitTester: AXHitTester
    private let dockFrameProvider: AXDockFrameProvider
    private let frontmostProvider = FrontmostAppProvider()
    private let minimizer = WindowMinimizer()
    private let debouncer: ClickDebouncer

    // MARK: - Init

    init() {
        self.debouncer = ClickDebouncer(
            window: ClickDebouncer.debounceInterval,
            now: { Date() }
        )

        self.hitTester = AXHitTester(
            frontmostLocalizedName: {
                NSWorkspace.shared.frontmostApplication?.localizedName
            }
        )

        self.dockFrameProvider = AXDockFrameProvider(
            dockPIDProvider: { [dockPIDCache] in dockPIDCache.pid }
        )
    }

    // MARK: - Lifecycle

    /// Installs the global click monitor. Idempotent.
    func start() {
        clickMonitor.start { [weak self] point in
            dispatchPrecondition(condition: .onQueue(.main))
            guard let self else { return }
            os_log("pipeline: click received at (%{public}.1f, %{public}.1f)",
                   log: Log.pipeline, type: .info, point.x, point.y)
            self.runDiagnosticPipeline(nsEventPoint: point)
        }
        os_log("DockWatcher started", log: Log.lifecycle, type: .info)
    }

    /// Tears down the global click monitor. Safe to call when not running.
    func stop() {
        clickMonitor.stop()
        os_log("DockWatcher stopped", log: Log.lifecycle, type: .info)
    }

    // MARK: - Diagnostic pipeline (mirrors Core.runClickPipeline with logs)

    /// Identical to `runClickPipeline` but emits an os_log at every
    /// early-return so we can see exactly where a click gets dropped.
    /// Keep in sync with `ClickPipeline.swift` until we're done debugging.
    private func runDiagnosticPipeline(nsEventPoint: CGPoint) {
        let converter = CoordinateConverter(screenFrames: NSScreen.screens.map(\.frame))
        let axPoint = converter.toAX(nsEventPoint)
        os_log("pipeline: ax point (%{public}.1f, %{public}.1f)",
               log: Log.pipeline, type: .info, axPoint.x, axPoint.y)

        let geometry = DockGeometry(provider: dockFrameProvider)
        guard geometry.contains(axPoint) else {
            os_log("pipeline: drop at contains (frame=%{public}@)",
                   log: Log.pipeline, type: .info,
                   dockFrameProvider.frame.map { NSStringFromRect($0) } ?? "nil")
            return
        }

        guard let element = hitTester.hitTest(at: axPoint) else {
            os_log("pipeline: drop at hitTest (nil)", log: Log.pipeline, type: .info)
            return
        }

        guard let dockPid = dockPIDCache.pid else {
            os_log("pipeline: drop at dockPID (nil)", log: Log.pipeline, type: .info)
            return
        }

        let hitPid = hitTester.pid(element) ?? -1
        guard hitPid == dockPid else {
            os_log("pipeline: drop at pid mismatch (hit=%{public}d dock=%{public}d)",
                   log: Log.pipeline, type: .info, hitPid, dockPid)
            return
        }

        guard let itemURL = hitTester.dockItemURL(element) else {
            os_log("pipeline: drop at dockItemURL (nil)", log: Log.pipeline, type: .info)
            return
        }
        os_log("pipeline: dock item url = %{public}@",
               log: Log.pipeline, type: .info, itemURL.absoluteString)

        guard let front = frontmostProvider.frontmostPidAndURL else {
            os_log("pipeline: drop at frontmost (nil)", log: Log.pipeline, type: .info)
            return
        }
        os_log("pipeline: frontmost pid=%{public}d url=%{public}@",
               log: Log.pipeline, type: .info,
               front.pid, front.bundleURL?.absoluteString ?? "nil")

        guard BundleURLMatcher.matches(itemURL, front.bundleURL) else {
            os_log("pipeline: drop at url mismatch", log: Log.pipeline, type: .info)
            return
        }

        guard debouncer.shouldAllow(itemID: itemURL.absoluteString) else {
            os_log("pipeline: drop at debounce", log: Log.pipeline, type: .info)
            return
        }

        minimizer.minimizeFocusedWindow(ofPid: front.pid, bundleURL: front.bundleURL)
    }
}
