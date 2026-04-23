import CoreGraphics
import Foundation

/// Dependencies for a single click-pipeline invocation.
///
/// All closures and protocol references are injected by the coordinator
/// (`DockWatcher`) so the pipeline is fully testable with in-memory fakes.
public struct ClickPipelineDeps {
    public let screenFrames: () -> [CGRect]
    public let dockFrame: DockFrameProvider
    public let hitTester: HitTesting
    public let dockPID: DockPIDProviding
    public let minimizer: WindowMinimizing
    public let frontmost: FrontmostAppInfoProviding
    public let debouncer: ClickDebouncer

    public init(
        screenFrames: @escaping () -> [CGRect],
        dockFrame: DockFrameProvider,
        hitTester: HitTesting,
        dockPID: DockPIDProviding,
        minimizer: WindowMinimizing,
        frontmost: FrontmostAppInfoProviding,
        debouncer: ClickDebouncer
    ) {
        self.screenFrames = screenFrames
        self.dockFrame = dockFrame
        self.hitTester = hitTester
        self.dockPID = dockPID
        self.minimizer = minimizer
        self.frontmost = frontmost
        self.debouncer = debouncer
    }
}

/// Runs one click through the pipeline. No branching beyond `guard` early-returns.
///
/// Thread contract: caller must invoke on main (AX thread affinity).
///
/// Pipeline order is load-bearing — reordering breaks `DockWatcherPipelineTests`.
///
/// Pipeline sequence:
/// ```
/// CoordinateConverter → DockGeometry.contains
///   → hitTest → pid check → dockItemURL
///   → frontmost → BundleURLMatcher → debouncer
///   → minimize
/// ```
public func runClickPipeline(nsEventPoint: CGPoint, deps: ClickPipelineDeps) {
    let converter = CoordinateConverter(screenFrames: deps.screenFrames())
    let axPoint = converter.toAX(nsEventPoint)

    let geometry = DockGeometry(provider: deps.dockFrame)
    guard geometry.contains(axPoint) else { return }

    guard let element = deps.hitTester.hitTest(at: axPoint) else { return }

    guard let dockPid = deps.dockPID.pid,
          deps.hitTester.pid(element) == dockPid else { return }

    guard let itemURL = deps.hitTester.dockItemURL(element) else { return }

    guard let front = deps.frontmost.frontmostPidAndURL else { return }

    guard BundleURLMatcher.matches(itemURL, front.bundleURL) else { return }

    guard deps.debouncer.shouldAllow(itemID: itemURL.absoluteString) else { return }

    deps.minimizer.minimizeFocusedWindow(ofPid: front.pid, bundleURL: front.bundleURL)
}
