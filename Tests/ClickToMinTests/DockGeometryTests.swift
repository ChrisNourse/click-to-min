import XCTest
import CoreGraphics
@testable import ClickToMinCore

// MARK: - Test double

/// Mutable fake that allows tests to change the frame between calls,
/// simulating Dock resize / move / auto-hide.
private final class FakeDockFrameProvider: DockFrameProvider {
    var frame: CGRect?
    init(frame: CGRect?) { self.frame = frame }
}

// MARK: - Tests

final class DockGeometryTests: XCTestCase {

    // MARK: - Dock at bottom of screen

    /// Typical bottom Dock: full width, 70pt tall at the bottom.
    /// AX coordinates: top-left origin. Dock at y 930..1000 on a 1000pt-tall space.
    func testBottomDock_insidePoint() {
        let provider = FakeDockFrameProvider(frame: CGRect(x: 0, y: 930, width: 1440, height: 70))
        let geo = DockGeometry(provider: provider)

        XCTAssertTrue(geo.contains(CGPoint(x: 720, y: 960)))
    }

    func testBottomDock_outsidePoint() {
        let provider = FakeDockFrameProvider(frame: CGRect(x: 0, y: 930, width: 1440, height: 70))
        let geo = DockGeometry(provider: provider)

        // Point above the Dock region.
        XCTAssertFalse(geo.contains(CGPoint(x: 720, y: 500)))
    }

    // MARK: - Dock on left side

    func testLeftDock_insidePoint() {
        // Dock on the left: 70pt wide, full height.
        let provider = FakeDockFrameProvider(frame: CGRect(x: 0, y: 0, width: 70, height: 900))
        let geo = DockGeometry(provider: provider)

        XCTAssertTrue(geo.contains(CGPoint(x: 35, y: 450)))
    }

    func testLeftDock_outsidePoint() {
        let provider = FakeDockFrameProvider(frame: CGRect(x: 0, y: 0, width: 70, height: 900))
        let geo = DockGeometry(provider: provider)

        XCTAssertFalse(geo.contains(CGPoint(x: 100, y: 450)))
    }

    // MARK: - Dock on right side

    func testRightDock_insidePoint() {
        let provider = FakeDockFrameProvider(frame: CGRect(x: 1370, y: 0, width: 70, height: 900))
        let geo = DockGeometry(provider: provider)

        XCTAssertTrue(geo.contains(CGPoint(x: 1400, y: 450)))
    }

    func testRightDock_outsidePoint() {
        let provider = FakeDockFrameProvider(frame: CGRect(x: 1370, y: 0, width: 70, height: 900))
        let geo = DockGeometry(provider: provider)

        XCTAssertFalse(geo.contains(CGPoint(x: 1300, y: 450)))
    }

    // MARK: - Edge inclusion (on-edge → true)

    func testOnEdge_minXminY() {
        let provider = FakeDockFrameProvider(frame: CGRect(x: 100, y: 200, width: 300, height: 50))
        let geo = DockGeometry(provider: provider)

        // Exactly on the top-left corner of the rect.
        XCTAssertTrue(geo.contains(CGPoint(x: 100, y: 200)))
    }

    func testOnEdge_maxXmaxY() {
        let provider = FakeDockFrameProvider(frame: CGRect(x: 100, y: 200, width: 300, height: 50))
        let geo = DockGeometry(provider: provider)

        // Exactly on the bottom-right corner (maxX=400, maxY=250).
        XCTAssertTrue(geo.contains(CGPoint(x: 400, y: 250)))
    }

    // MARK: - Off-by-one boundary

    func testOffByOne_justOutsideMaxX() {
        let frame = CGRect(x: 100, y: 200, width: 300, height: 50)
        let provider = FakeDockFrameProvider(frame: frame)
        let geo = DockGeometry(provider: provider)

        // frame.maxX = 400. Point at 400 is ON edge (included).
        XCTAssertTrue(geo.contains(CGPoint(x: 400, y: 225)))
        // Point at 400.001 is outside.
        XCTAssertFalse(geo.contains(CGPoint(x: 400.001, y: 225)))
    }

    func testOffByOne_justOutsideMaxY() {
        let frame = CGRect(x: 100, y: 200, width: 300, height: 50)
        let provider = FakeDockFrameProvider(frame: frame)
        let geo = DockGeometry(provider: provider)

        // frame.maxY = 250. ON edge → true.
        XCTAssertTrue(geo.contains(CGPoint(x: 200, y: 250)))
        // Just outside → false.
        XCTAssertFalse(geo.contains(CGPoint(x: 200, y: 250.001)))
    }

    func testOffByOne_justOutsideMinX() {
        let frame = CGRect(x: 100, y: 200, width: 300, height: 50)
        let provider = FakeDockFrameProvider(frame: frame)
        let geo = DockGeometry(provider: provider)

        XCTAssertTrue(geo.contains(CGPoint(x: 100, y: 225)))
        XCTAssertFalse(geo.contains(CGPoint(x: 99.999, y: 225)))
    }

    // MARK: - Nil frame → false

    func testNilFrame_returnsFalse() {
        let provider = FakeDockFrameProvider(frame: nil)
        let geo = DockGeometry(provider: provider)

        XCTAssertFalse(geo.contains(CGPoint(x: 720, y: 960)))
    }

    // MARK: - Frame change between calls (mutable provider)

    func testFrameChange_viaProvider() {
        let provider = FakeDockFrameProvider(frame: CGRect(x: 0, y: 930, width: 1440, height: 70))
        let geo = DockGeometry(provider: provider)

        // Initially inside.
        XCTAssertTrue(geo.contains(CGPoint(x: 720, y: 960)))

        // Simulate Dock moved to left side.
        provider.frame = CGRect(x: 0, y: 0, width: 70, height: 900)

        // Same point no longer inside.
        XCTAssertFalse(geo.contains(CGPoint(x: 720, y: 960)))
        // New region is inside.
        XCTAssertTrue(geo.contains(CGPoint(x: 35, y: 450)))
    }

    func testFrameChange_toNil() {
        let provider = FakeDockFrameProvider(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let geo = DockGeometry(provider: provider)

        XCTAssertTrue(geo.contains(CGPoint(x: 50, y: 50)))

        // Dock mid-relaunch — frame unknown.
        provider.frame = nil
        XCTAssertFalse(geo.contains(CGPoint(x: 50, y: 50)))
    }
}
