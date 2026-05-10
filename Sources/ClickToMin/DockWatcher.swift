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

    private static let rapidClickDelay: TimeInterval = 0.05

    func injectTestClick(spec: TestClickSpec, resultPath: String) {
        switch spec.mode {
        case .right, .ctrl:
            injectFilteredClick(spec: spec, resultPath: resultPath)
        case let .rapid(count):
            injectRapidClicks(at: spec.point, count: count, resultPath: resultPath)
        case .normal:
            injectNormalClick(at: spec.point, resultPath: resultPath)
        }
    }

    private func injectFilteredClick(spec: TestClickSpec, resultPath: String) {
        let modeLabel = if case .right = spec.mode { "right" } else { "ctrl" }
        os_log("pipeline: injected filtered test click (mode=%{public}@)",
               log: Log.pipeline, type: .info, modeLabel)
        try? "done:rejected".write(toFile: resultPath, atomically: true, encoding: .utf8)
    }

    private func injectRapidClicks(at point: CGPoint, count: Int, resultPath: String) {
        os_log("pipeline: injected rapid test clicks (count=%{public}d)",
               log: Log.pipeline, type: .info, count)
        var dispatched = 0
        for idx in 0 ..< count {
            if idx > 0 {
                Thread.sleep(forTimeInterval: DockWatcher.rapidClickDelay)
            }
            if runPipelineForInjection(at: point) {
                dispatched += 1
            }
        }
        let debounced = count - dispatched
        try? "done:debounced:\(debounced)".write(
            toFile: resultPath, atomically: true, encoding: .utf8
        )
    }

    private func injectNormalClick(at axPoint: CGPoint, resultPath: String) {
        os_log("pipeline: injected test click at AX (%{public}.1f, %{public}.1f)",
               log: Log.pipeline, type: .info, axPoint.x, axPoint.y)
        let startTime = CFAbsoluteTimeGetCurrent()
        let minimized = runPipelineForInjection(at: axPoint)
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        if minimized {
            try? "done:timing_ms=\(elapsedMs)".write(
                toFile: resultPath, atomically: true, encoding: .utf8
            )
        } else {
            try? "done:no-minimize:timing_ms=\(elapsedMs)".write(
                toFile: resultPath, atomically: true, encoding: .utf8
            )
        }
    }

    @discardableResult
    private func runPipelineForInjection(at axPoint: CGPoint) -> Bool {
        let geometry = DockGeometry(provider: dockFrameProvider)
        guard geometry.contains(axPoint) else {
            os_log("pipeline: test-click drop at contains (frame=%{public}@)",
                   log: Log.pipeline, type: .info,
                   dockFrameProvider.frame.map { NSStringFromRect($0) } ?? "nil")
            return false
        }

        guard let element = hitTester.hitTest(at: axPoint) else {
            os_log("pipeline: test-click drop at hitTest (nil)", log: Log.pipeline, type: .info)
            return false
        }

        guard let dockPid = dockPIDCache.pid else {
            os_log("pipeline: test-click drop at dockPID (nil)", log: Log.pipeline, type: .info)
            return false
        }

        let hitPid = hitTester.pid(element) ?? -1
        guard hitPid == dockPid else {
            os_log("pipeline: test-click drop at pid mismatch (hit=%{public}d dock=%{public}d)",
                   log: Log.pipeline, type: .info, hitPid, dockPid)
            return false
        }

        guard let itemURL = hitTester.dockItemURL(element) else {
            os_log("pipeline: test-click drop at dockItemURL (nil)", log: Log.pipeline, type: .info)
            return false
        }

        guard let front = frontmostProvider.frontmostPidAndURL else {
            os_log("pipeline: test-click drop at frontmost (nil)", log: Log.pipeline, type: .info)
            return false
        }

        guard BundleURLMatcher.matches(itemURL, front.bundleURL) else {
            os_log("pipeline: test-click drop at url mismatch", log: Log.pipeline, type: .info)
            return false
        }

        guard debouncer.shouldAllow(itemID: itemURL.absoluteString) else {
            os_log("pipeline: test-click drop at debounce", log: Log.pipeline, type: .info)
            return false
        }

        minimizer.minimizeFocusedWindow(ofPid: front.pid, bundleURL: front.bundleURL)
        os_log("pipeline: test-click minimize dispatched", log: Log.pipeline, type: .info)
        return true
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
