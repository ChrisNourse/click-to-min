import CoreGraphics
import Foundation
import XCTest
@testable import AXProbe

final class FakeAXReader: AXReader {
    var trusted = true
    var frontmost: String? = "com.apple.Safari"
    var minimizedByBundle: [String: Bool?] = [:]
    var windowCounts: [String: Int?] = [:]
    var dockFrames: [String: CGRect?] = [:]

    func isProcessTrusted() -> Bool { trusted }
    func frontmostBundleId() -> String? { frontmost }
    func focusedWindowMinimized(bundleId: String) -> Bool? {
        minimizedByBundle[bundleId] ?? nil
    }
    func anyWindowMinimized(bundleId: String) -> Bool? {
        minimizedByBundle[bundleId] ?? nil
    }
    func windowCount(bundleId: String) -> Int? { windowCounts[bundleId] ?? nil }
    func dockItemFrame(bundleId: String) -> CGRect? { dockFrames[bundleId] ?? nil }
}

final class ProbeTests: XCTestCase {
    func test_isTrusted_returnsZeroWhenTrusted() {
        let r = FakeAXReader()
        r.trusted = true
        XCTAssertEqual(Probe.run(args: ["is-trusted"], reader: r), 0)
    }

    func test_isTrusted_returnsThreeWhenNotTrusted() {
        let r = FakeAXReader()
        r.trusted = false
        XCTAssertEqual(Probe.run(args: ["is-trusted"], reader: r), 3)
    }

    func test_frontmostBundleId_printsIdAndExitsZero() {
        let r = FakeAXReader()
        r.frontmost = "com.apple.Safari"
        XCTAssertEqual(Probe.run(args: ["frontmost-bundle-id"], reader: r), 0)
    }

    func test_frontmostBundleId_failsWhenNil() {
        let r = FakeAXReader()
        r.frontmost = nil
        XCTAssertEqual(Probe.run(args: ["frontmost-bundle-id"], reader: r), 1)
    }

    func test_isMinimized_requiresArgument() {
        let r = FakeAXReader()
        XCTAssertEqual(Probe.run(args: ["is-minimized"], reader: r), 1)
    }

    func test_isMinimized_requiresAccessibility() {
        let r = FakeAXReader()
        r.trusted = false
        XCTAssertEqual(Probe.run(args: ["is-minimized", "x"], reader: r), 3)
    }

    func test_isMinimized_trueCase() {
        let r = FakeAXReader()
        r.minimizedByBundle["x"] = true
        XCTAssertEqual(Probe.run(args: ["is-minimized", "x"], reader: r), 0)
    }

    func test_isMinimized_returnsFailureWhenReaderReturnsNil() {
        let r = FakeAXReader()
        r.minimizedByBundle["x"] = Bool?.none
        XCTAssertEqual(Probe.run(args: ["is-minimized", "x"], reader: r), 1)
    }

    func test_windowCount_okAndMissing() {
        let r = FakeAXReader()
        r.windowCounts["x"] = 3
        XCTAssertEqual(Probe.run(args: ["window-count", "x"], reader: r), 0)
        r.windowCounts["x"] = Int?.none
        XCTAssertEqual(Probe.run(args: ["window-count", "x"], reader: r), 1)
    }

    func test_waitUntilMinimized_timesOutQuickly() {
        let r = FakeAXReader()
        r.minimizedByBundle["x"] = false
        let rc = Probe.run(
            args: ["wait-until-minimized", "x", "--timeout", "0.1"],
            reader: r
        )
        XCTAssertEqual(rc, 2)
    }

    func test_waitUntilMinimized_succeeds() {
        let r = FakeAXReader()
        r.minimizedByBundle["x"] = true
        let rc = Probe.run(
            args: ["wait-until-minimized", "x", "--timeout", "0.5"],
            reader: r
        )
        XCTAssertEqual(rc, 0)
    }

    func test_dockItemFrame_printsXYWH() {
        let r = FakeAXReader()
        r.dockFrames["x"] = CGRect(x: 100, y: 200, width: 64, height: 64)
        XCTAssertEqual(Probe.run(args: ["dock-item-frame", "x"], reader: r), 0)
    }

    func test_dockItemFrame_failsWhenMissing() {
        let r = FakeAXReader()
        r.dockFrames["x"] = CGRect?.none
        XCTAssertEqual(Probe.run(args: ["dock-item-frame", "x"], reader: r), 1)
    }

    func test_unknownSubcommandFails() {
        let r = FakeAXReader()
        XCTAssertEqual(Probe.run(args: ["nope"], reader: r), 1)
    }

    func test_helpExitsZero() {
        let r = FakeAXReader()
        XCTAssertEqual(Probe.run(args: ["--help"], reader: r), 0)
    }

    func test_noArgsPrintsUsageAndFails() {
        let r = FakeAXReader()
        XCTAssertEqual(Probe.run(args: [], reader: r), 1)
    }
}
