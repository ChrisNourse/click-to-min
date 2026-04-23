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

    // MARK: - Pipeline deps (built once, used per click)

    private let deps: ClickPipelineDeps

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

        self.deps = ClickPipelineDeps(
            screenFrames: { NSScreen.screens.map(\.frame) },
            dockFrame: dockFrameProvider,
            hitTester: hitTester,
            dockPID: dockPIDCache,
            minimizer: minimizer,
            frontmost: frontmostProvider,
            debouncer: debouncer
        )
    }

    // MARK: - Lifecycle

    /// Installs the global click monitor. Idempotent.
    func start() {
        clickMonitor.start { [weak self] point in
            dispatchPrecondition(condition: .onQueue(.main))
            guard let self else { return }
            runClickPipeline(nsEventPoint: point, deps: self.deps)
        }
        os_log("DockWatcher started", log: Log.lifecycle, type: .info)
    }

    /// Tears down the global click monitor. Safe to call when not running.
    func stop() {
        clickMonitor.stop()
        os_log("DockWatcher stopped", log: Log.lifecycle, type: .info)
    }
}
