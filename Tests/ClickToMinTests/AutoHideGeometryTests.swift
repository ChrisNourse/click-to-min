import CoreGraphics
import XCTest

@testable import ClickToMinCore

// MARK: - DockOrientation

final class DockOrientationTests: XCTestCase {

    func testRawPreference_bottom() {
        XCTAssertEqual(DockOrientation(rawPreference: "bottom"), .bottom)
    }

    func testRawPreference_left() {
        XCTAssertEqual(DockOrientation(rawPreference: "left"), .left)
    }

    func testRawPreference_right() {
        XCTAssertEqual(DockOrientation(rawPreference: "right"), .right)
    }

    func testRawPreference_nil_defaultsToBottom() {
        XCTAssertEqual(DockOrientation(rawPreference: nil), .bottom)
    }

    func testRawPreference_unknown_defaultsToBottom() {
        XCTAssertEqual(DockOrientation(rawPreference: "top"), .bottom)
        XCTAssertEqual(DockOrientation(rawPreference: ""), .bottom)
    }
}

// MARK: - adjustFrameForAutoHide

final class AutoHideGeometryTests: XCTestCase {

    /// Standard 1440×900 screen at origin.
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    /// Dock at bottom of screen (AX coords: y=850..900).
    private let bottomDock = CGRect(x: 200, y: 850, width: 1040, height: 50)

    /// Dock on left edge.
    private let leftDock = CGRect(x: 0, y: 200, width: 60, height: 500)

    /// Dock on right edge.
    private let rightDock = CGRect(x: 1380, y: 200, width: 60, height: 500)

    // MARK: - Bottom orientation

    func testBottom_extendsToScreenBottom() {
        let result = adjustFrameForAutoHide(
            rawFrame: bottomDock, orientation: .bottom,
            screenFrame: screen, stripWidth: 5
        )
        XCTAssertEqual(result.minY, 0,
                       "strip at bottom (AX origin=top-left, so minY=0 is screen top — "
                       + "but union with raw frame means minY is min of both)")
        XCTAssertTrue(result.contains(CGPoint(x: 720, y: 2)),
                      "should include points in 5pt bottom strip")
        XCTAssertTrue(result.contains(CGPoint(x: 720, y: 875)),
                      "should still include original dock frame")
    }

    func testBottom_fullWidthStrip() {
        let result = adjustFrameForAutoHide(
            rawFrame: bottomDock, orientation: .bottom,
            screenFrame: screen, stripWidth: 5
        )
        XCTAssertEqual(result.minX, 0, "strip spans full screen width")
        XCTAssertEqual(result.width, 1440, "strip spans full screen width")
    }

    // MARK: - Left orientation

    func testLeft_extendsToScreenLeft() {
        let result = adjustFrameForAutoHide(
            rawFrame: leftDock, orientation: .left,
            screenFrame: screen, stripWidth: 5
        )
        XCTAssertEqual(result.minX, 0)
        XCTAssertTrue(result.contains(CGPoint(x: 2, y: 100)),
                      "should include points in 5pt left strip")
        XCTAssertTrue(result.contains(CGPoint(x: 30, y: 400)),
                      "should still include original dock frame")
    }

    func testLeft_fullHeightStrip() {
        let result = adjustFrameForAutoHide(
            rawFrame: leftDock, orientation: .left,
            screenFrame: screen, stripWidth: 5
        )
        XCTAssertEqual(result.minY, 0, "strip spans full screen height")
        XCTAssertEqual(result.height, 900, "strip spans full screen height")
    }

    // MARK: - Right orientation

    func testRight_extendsToScreenRight() {
        let result = adjustFrameForAutoHide(
            rawFrame: rightDock, orientation: .right,
            screenFrame: screen, stripWidth: 5
        )
        XCTAssertEqual(result.maxX, 1440)
        XCTAssertTrue(result.contains(CGPoint(x: 1438, y: 100)),
                      "should include points in 5pt right strip")
        XCTAssertTrue(result.contains(CGPoint(x: 1400, y: 400)),
                      "should still include original dock frame")
    }

    func testRight_fullHeightStrip() {
        let result = adjustFrameForAutoHide(
            rawFrame: rightDock, orientation: .right,
            screenFrame: screen, stripWidth: 5
        )
        XCTAssertEqual(result.minY, 0, "strip spans full screen height")
        XCTAssertEqual(result.height, 900, "strip spans full screen height")
    }

    // MARK: - Custom strip width

    func testCustomStripWidth_bottom() {
        let result = adjustFrameForAutoHide(
            rawFrame: bottomDock, orientation: .bottom,
            screenFrame: screen, stripWidth: 10
        )
        XCTAssertTrue(result.contains(CGPoint(x: 720, y: 8)),
                      "10pt strip should include points at y=8")
    }

    // MARK: - Union preserves original frame

    func testUnion_alwaysContainsOriginalFrame() {
        for orientation in [DockOrientation.bottom, .left, .right] {
            let result = adjustFrameForAutoHide(
                rawFrame: bottomDock, orientation: orientation,
                screenFrame: screen, stripWidth: 5
            )
            XCTAssertTrue(result.contains(bottomDock),
                          "adjusted frame must contain original for \(orientation)")
        }
    }

    // MARK: - Non-origin screen

    func testNonOriginScreen_left() {
        let secondScreen = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let dock = CGRect(x: 1440, y: 200, width: 60, height: 680)
        let result = adjustFrameForAutoHide(
            rawFrame: dock, orientation: .left,
            screenFrame: secondScreen, stripWidth: 5
        )
        XCTAssertEqual(result.minX, 1440, "strip starts at second screen origin")
        XCTAssertTrue(result.contains(CGPoint(x: 1442, y: 500)))
    }

    func testNonOriginScreen_right() {
        let secondScreen = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let dock = CGRect(x: 3300, y: 200, width: 60, height: 680)
        let result = adjustFrameForAutoHide(
            rawFrame: dock, orientation: .right,
            screenFrame: secondScreen, stripWidth: 5
        )
        XCTAssertEqual(result.maxX, 3360, "strip ends at second screen edge")
    }
}
