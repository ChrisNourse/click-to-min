// DockWatcherPipelineTests
//
// Regression guard for the click pipeline contract.
// If you reorder runClickPipeline, the sequence test will fail.
//
// All tests use in-memory fakes that record invocations into a shared
// ordered log, enabling both behavior and call-order assertions.

import CoreGraphics
import Foundation
import XCTest

@testable import ClickToMinCore

// MARK: - Shared invocation log

/// Thread-unsafe (tests are single-threaded) ordered log of calls.
final class CallLog {
    private(set) var entries: [String] = []
    func record(_ entry: String) { entries.append(entry) }
    func reset() { entries.removeAll() }
}

// MARK: - Fakes

/// DockFrameProvider is `AnyObject`-constrained, so this must be a class.
final class FakeDockFrameProvider: DockFrameProvider {
    let log: CallLog
    var stubbedFrame: CGRect?

    init(log: CallLog, frame: CGRect? = nil) {
        self.log = log
        self.stubbedFrame = frame
    }

    var frame: CGRect? {
        log.record("dockFrame")
        return stubbedFrame
    }
}

final class FakeHitTester: HitTesting {
    let log: CallLog
    var stubbedElement: AnyObject?
    var stubbedPID: pid_t?
    var stubbedURL: URL?

    init(log: CallLog) {
        self.log = log
    }

    func hitTest(at point: CGPoint) -> AnyObject? {
        log.record("hitTest")
        return stubbedElement
    }

    func pid(_ element: AnyObject) -> pid_t? {
        log.record("pid")
        return stubbedPID
    }

    func dockItemURL(_ element: AnyObject) -> URL? {
        log.record("dockItemURL")
        return stubbedURL
    }
}

final class FakeDockPIDProviding: DockPIDProviding {
    let log: CallLog
    var stubbedPID: pid_t?

    init(log: CallLog, pid: pid_t? = nil) {
        self.log = log
        self.stubbedPID = pid
    }

    var pid: pid_t? {
        log.record("dockPID")
        return stubbedPID
    }
}

final class FakeWindowMinimizer: WindowMinimizing {
    let log: CallLog
    var capturedPid: pid_t?
    var capturedBundleURL: URL?
    var callCount = 0

    init(log: CallLog) {
        self.log = log
    }

    func minimizeFocusedWindow(ofPid pid: pid_t, bundleURL: URL?) {
        log.record("minimize")
        capturedPid = pid
        capturedBundleURL = bundleURL
        callCount += 1
    }
}

final class FakeFrontmostAppInfoProviding: FrontmostAppInfoProviding {
    let log: CallLog
    var stubbedResult: (pid: pid_t, bundleURL: URL?)?

    init(log: CallLog) {
        self.log = log
    }

    var frontmostPidAndURL: (pid: pid_t, bundleURL: URL?)? {
        log.record("frontmost")
        return stubbedResult
    }
}

// MARK: - Helpers

/// A simple `NSObject` to serve as a fake AX element.
private final class FakeElement: NSObject {}

/// Standard screen: 1440×900 primary screen at origin (0, 0).
private let singleScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)

/// Dock rect at bottom of screen (AX coords: top-left origin).
/// AX Y increases downward, so bottom dock has large Y values.
/// For a 1440×900 screen, the Dock might be at y=850..900.
private let bottomDockRect = CGRect(x: 0, y: 850, width: 1440, height: 50)

/// A click inside the Dock in NSEvent coords (bottom-left origin).
/// NSEvent y=25 → AX y = 900 - 25 = 875, which is inside bottomDockRect.
private let clickInsideDockNS = CGPoint(x: 720, y: 25)

/// A click outside the Dock in NSEvent coords.
/// NSEvent y=500 → AX y = 900 - 500 = 400, which is outside bottomDockRect.
private let clickOutsideDockNS = CGPoint(x: 720, y: 500)

private let safariURL = URL(string: "file:///Applications/Safari.app")!
private let safariPid: pid_t = 1234
private let dockPid: pid_t = 99

// MARK: - Test suite

final class DockWatcherPipelineTests: XCTestCase {

    private var log: CallLog!
    private var dockFrame: FakeDockFrameProvider!
    private var hitTester: FakeHitTester!
    private var dockPIDProvider: FakeDockPIDProviding!
    private var minimizer: FakeWindowMinimizer!
    private var frontmost: FakeFrontmostAppInfoProviding!
    private var fixedDate: Date!
    private var debouncer: ClickDebouncer!

    override func setUp() {
        super.setUp()
        log = CallLog()
        dockFrame = FakeDockFrameProvider(log: log, frame: bottomDockRect)
        hitTester = FakeHitTester(log: log)
        dockPIDProvider = FakeDockPIDProviding(log: log, pid: dockPid)
        minimizer = FakeWindowMinimizer(log: log)
        frontmost = FakeFrontmostAppInfoProviding(log: log)

        fixedDate = Date(timeIntervalSinceReferenceDate: 1000)
        debouncer = ClickDebouncer(
            window: ClickDebouncer.debounceInterval,
            now: { [self] in self.fixedDate }
        )
    }

    private func makeDeps() -> ClickPipelineDeps {
        ClickPipelineDeps(
            screenFrames: { [singleScreen] },
            dockFrame: dockFrame,
            hitTester: hitTester,
            dockPID: dockPIDProvider,
            minimizer: minimizer,
            frontmost: frontmost,
            debouncer: debouncer
        )
    }

    /// Configures all fakes for a happy-path invocation.
    private func configureHappyPath() {
        let element = FakeElement()
        hitTester.stubbedElement = element
        hitTester.stubbedPID = dockPid
        hitTester.stubbedURL = safariURL
        frontmost.stubbedResult = (pid: safariPid, bundleURL: safariURL)
    }

    // MARK: - Test 1: Click outside Dock

    func testClickOutsideDock_stopsAtContains_hitTesterNotCalled() {
        configureHappyPath()

        runClickPipeline(nsEventPoint: clickOutsideDockNS, deps: makeDeps())

        // dockFrame.frame is accessed by DockGeometry.contains
        XCTAssertTrue(log.entries.contains("dockFrame"),
                      "DockGeometry should query the dock frame")
        XCTAssertFalse(log.entries.contains("hitTest"),
                       "hitTester should NOT be called when click is outside Dock")
        XCTAssertEqual(minimizer.callCount, 0)
    }

    // MARK: - Test 2: Click inside Dock, hitTester returns nil

    func testHitTestReturnsNil_stops() {
        hitTester.stubbedElement = nil  // hitTest returns nil
        hitTester.stubbedPID = dockPid
        hitTester.stubbedURL = safariURL
        frontmost.stubbedResult = (pid: safariPid, bundleURL: safariURL)

        runClickPipeline(nsEventPoint: clickInsideDockNS, deps: makeDeps())

        XCTAssertTrue(log.entries.contains("hitTest"))
        XCTAssertFalse(log.entries.contains("pid"),
                       "pid check should not be reached when hitTest returns nil")
        XCTAssertEqual(minimizer.callCount, 0)
    }

    // MARK: - Test 3: PID mismatch

    func testPIDMismatch_stops() {
        let element = FakeElement()
        hitTester.stubbedElement = element
        hitTester.stubbedPID = 999  // not the dock PID
        hitTester.stubbedURL = safariURL
        frontmost.stubbedResult = (pid: safariPid, bundleURL: safariURL)

        runClickPipeline(nsEventPoint: clickInsideDockNS, deps: makeDeps())

        XCTAssertTrue(log.entries.contains("pid"))
        XCTAssertFalse(log.entries.contains("dockItemURL"),
                       "dockItemURL should not be reached on PID mismatch")
        XCTAssertEqual(minimizer.callCount, 0)
    }

    // MARK: - Test 4: Dock PID nil (mid-relaunch)

    func testDockPIDNil_abortsSafely() {
        dockPIDProvider.stubbedPID = nil

        let element = FakeElement()
        hitTester.stubbedElement = element
        hitTester.stubbedPID = dockPid
        hitTester.stubbedURL = safariURL
        frontmost.stubbedResult = (pid: safariPid, bundleURL: safariURL)

        runClickPipeline(nsEventPoint: clickInsideDockNS, deps: makeDeps())

        XCTAssertTrue(log.entries.contains("dockPID"))
        XCTAssertFalse(log.entries.contains("dockItemURL"),
                       "pipeline should abort when dock PID is nil")
        XCTAssertEqual(minimizer.callCount, 0)
    }

    // MARK: - Test 5: URL mismatch

    func testURLMismatch_minimizerNeverCalled() {
        let element = FakeElement()
        hitTester.stubbedElement = element
        hitTester.stubbedPID = dockPid
        hitTester.stubbedURL = URL(string: "file:///Applications/Mail.app")!

        frontmost.stubbedResult = (pid: safariPid, bundleURL: safariURL)

        runClickPipeline(nsEventPoint: clickInsideDockNS, deps: makeDeps())

        XCTAssertTrue(log.entries.contains("frontmost"))
        XCTAssertFalse(log.entries.contains("minimize"),
                       "minimizer should NOT be called on URL mismatch")
        XCTAssertEqual(minimizer.callCount, 0)
    }

    // MARK: - Test 6: URL match, debouncer suppresses

    func testDebouncerSuppresses_minimizerNeverCalled() {
        configureHappyPath()

        // First click goes through.
        runClickPipeline(nsEventPoint: clickInsideDockNS, deps: makeDeps())
        XCTAssertEqual(minimizer.callCount, 1)

        // Second click at same time — debouncer should suppress.
        log.reset()
        minimizer.callCount = 0
        runClickPipeline(nsEventPoint: clickInsideDockNS, deps: makeDeps())

        XCTAssertEqual(minimizer.callCount, 0,
                       "second click within debounce window should be suppressed")
    }

    // MARK: - Test 7: Happy path

    func testHappyPath_minimizerCalledOnceWithCorrectArgs() {
        configureHappyPath()

        runClickPipeline(nsEventPoint: clickInsideDockNS, deps: makeDeps())

        XCTAssertEqual(minimizer.callCount, 1)
        XCTAssertEqual(minimizer.capturedPid, safariPid)
        XCTAssertEqual(minimizer.capturedBundleURL, safariURL)
    }

    // MARK: - Test 8: Frontmost flips between calls

    /// runClickPipeline reads frontmost ONCE per click, so a flip after
    /// the read doesn't affect the decision. This test documents that
    /// behavior by changing `frontmost.stubbedResult` after initial
    /// configuration — the pipeline uses the value at read time.
    func testFrontmostFlip_decisionConsistentWithReadPoint() {
        configureHappyPath()

        // The pipeline reads frontmost once. Even if we change the stub
        // after the pipeline runs, the first invocation already captured
        // the original value. We verify by running, then flipping, then
        // running again with a mismatched URL.
        runClickPipeline(nsEventPoint: clickInsideDockNS, deps: makeDeps())
        XCTAssertEqual(minimizer.callCount, 1, "first click should minimize")

        // Advance time past debounce window for the second click.
        fixedDate = fixedDate.addingTimeInterval(1.0)
        log.reset()
        minimizer.callCount = 0

        // Flip frontmost to a different app.
        let mailURL = URL(string: "file:///Applications/Mail.app")!
        frontmost.stubbedResult = (pid: 5678, bundleURL: mailURL)

        // The dock item URL is still Safari, but frontmost is now Mail.
        // Pipeline reads frontmost at click time → mismatch → no minimize.
        runClickPipeline(nsEventPoint: clickInsideDockNS, deps: makeDeps())
        XCTAssertEqual(minimizer.callCount, 0,
                       "after frontmost flips, URL mismatch should prevent minimize")
    }

    // MARK: - Test 9: Exact call sequence on happy path

    func testHappyPath_exactCallSequence() {
        configureHappyPath()

        runClickPipeline(nsEventPoint: clickInsideDockNS, deps: makeDeps())

        // Pipeline order is load-bearing. This test catches reorders that
        // happen to produce the right outcome but break the contract.
        let expected = [
            "dockFrame",     // DockGeometry.contains checks the frame
            "hitTest",       // AXUIElementCopyElementAtPosition
            "dockPID",       // read cached Dock PID
            "pid",           // extract PID from hit element
            "dockItemURL",   // walk to AXDockItem, read kAXURLAttribute
            "frontmost",     // read frontmost app PID + bundle URL
            "minimize",      // minimizeFocusedWindow
        ]
        XCTAssertEqual(log.entries, expected,
                       "Pipeline call order must match the documented contract")
    }

    // MARK: - Test 10: Frontmost nil aborts

    func testFrontmostNil_minimizerNeverCalled() {
        let element = FakeElement()
        hitTester.stubbedElement = element
        hitTester.stubbedPID = dockPid
        hitTester.stubbedURL = safariURL
        frontmost.stubbedResult = nil  // no frontmost app

        runClickPipeline(nsEventPoint: clickInsideDockNS, deps: makeDeps())

        XCTAssertTrue(log.entries.contains("frontmost"))
        XCTAssertFalse(log.entries.contains("minimize"))
        XCTAssertEqual(minimizer.callCount, 0)
    }

    // MARK: - Test 11: dockItemURL nil stops pipeline

    func testDockItemURLNil_stops() {
        let element = FakeElement()
        hitTester.stubbedElement = element
        hitTester.stubbedPID = dockPid
        hitTester.stubbedURL = nil  // Finder/Trash/stack
        frontmost.stubbedResult = (pid: safariPid, bundleURL: safariURL)

        runClickPipeline(nsEventPoint: clickInsideDockNS, deps: makeDeps())

        XCTAssertTrue(log.entries.contains("dockItemURL"))
        XCTAssertFalse(log.entries.contains("frontmost"),
                       "frontmost should not be reached when dockItemURL is nil")
        XCTAssertEqual(minimizer.callCount, 0)
    }
}
