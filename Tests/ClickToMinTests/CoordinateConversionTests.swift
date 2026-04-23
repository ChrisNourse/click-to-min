import XCTest
import CoreGraphics
@testable import ClickToMinCore

final class CoordinateConversionTests: XCTestCase {

    // MARK: - Single screen (primary only)

    /// Primary screen: 1440×900, origin (0, 0).
    /// NSEvent point at bottom-left (100, 50) → AX top-left (100, 850).
    func testSingleScreen_bottomLeftToTopLeft() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let converter = CoordinateConverter(screenFrames: [primary])

        let ax = converter.toAX(CGPoint(x: 100, y: 50))

        XCTAssertEqual(ax.x, 100, accuracy: 0.001)
        // axY = primaryMaxY - nsEventY = 900 - 50 = 850
        XCTAssertEqual(ax.y, 850, accuracy: 0.001)
    }

    /// Top-left corner in NSEvent coords is (0, screenHeight).
    /// That should map to AX (0, 0).
    func testSingleScreen_topLeftCorner() {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let converter = CoordinateConverter(screenFrames: [primary])

        let ax = converter.toAX(CGPoint(x: 0, y: 1080))

        XCTAssertEqual(ax.x, 0, accuracy: 0.001)
        XCTAssertEqual(ax.y, 0, accuracy: 0.001)
    }

    /// Origin (0, 0) in NSEvent is bottom-left → AX (0, screenHeight).
    func testSingleScreen_bottomLeftCorner() {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let converter = CoordinateConverter(screenFrames: [primary])

        let ax = converter.toAX(CGPoint(x: 0, y: 0))

        XCTAssertEqual(ax.x, 0, accuracy: 0.001)
        XCTAssertEqual(ax.y, 1080, accuracy: 0.001)
    }

    // MARK: - Multi-screen: secondary to the right

    /// Primary (0, 0, 1440, 900), secondary (1440, 0, 1920, 1080) to the right.
    /// Click on secondary at NSEvent (1500, 200) → AX (1500, 700).
    func testMultiScreen_secondaryRight() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let converter = CoordinateConverter(screenFrames: [primary, secondary])

        let ax = converter.toAX(CGPoint(x: 1500, y: 200))

        XCTAssertEqual(ax.x, 1500, accuracy: 0.001)
        // axY = primaryMaxY - nsEventY = 900 - 200 = 700
        XCTAssertEqual(ax.y, 700, accuracy: 0.001)
    }

    // MARK: - Multi-screen: secondary to the left (negative origin)

    /// Secondary display left of primary → negative x origin.
    /// Primary (0, 0, 1440, 900), secondary (-1920, 0, 1920, 1080).
    /// Click on secondary at NSEvent (-500, 300) → AX (-500, 600).
    func testMultiScreen_secondaryLeft_negativeOrigin() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let converter = CoordinateConverter(screenFrames: [primary, secondary])

        let ax = converter.toAX(CGPoint(x: -500, y: 300))

        XCTAssertEqual(ax.x, -500, accuracy: 0.001)
        // axY = 900 - 300 = 600
        XCTAssertEqual(ax.y, 600, accuracy: 0.001)
    }

    // MARK: - Multi-screen: secondary above primary

    /// Secondary above primary → positive y origin in NSScreen (Y up).
    /// Primary (0, 0, 1440, 900), secondary (0, 900, 1920, 1080).
    /// Click on secondary at NSEvent (100, 1000) → AX (100, -100).
    func testMultiScreen_secondaryAbove() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = CGRect(x: 0, y: 900, width: 1920, height: 1080)
        let converter = CoordinateConverter(screenFrames: [primary, secondary])

        let ax = converter.toAX(CGPoint(x: 100, y: 1000))

        XCTAssertEqual(ax.x, 100, accuracy: 0.001)
        // axY = 900 - 1000 = -100
        XCTAssertEqual(ax.y, -100, accuracy: 0.001)
    }

    // MARK: - Multi-screen: secondary below primary

    /// Secondary below primary → negative y origin in NSScreen.
    /// Primary (0, 0, 1440, 900), secondary (0, -1080, 1920, 1080).
    /// Click on secondary at NSEvent (100, -500) → AX (100, 1400).
    func testMultiScreen_secondaryBelow() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        let converter = CoordinateConverter(screenFrames: [primary, secondary])

        let ax = converter.toAX(CGPoint(x: 100, y: -500))

        XCTAssertEqual(ax.x, 100, accuracy: 0.001)
        // axY = 900 - (-500) = 1400
        XCTAssertEqual(ax.y, 1400, accuracy: 0.001)
    }

    // MARK: - Retina (points, not pixels)

    /// Retina displays report frames in points. A 5K display might be
    /// 2560×1440 points. Conversion works in points throughout — no
    /// pixel scaling involved.
    func testRetina_pointsNotPixels() {
        // Simulates a Retina 5K: 2560×1440 in points.
        let primary = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let converter = CoordinateConverter(screenFrames: [primary])

        let ax = converter.toAX(CGPoint(x: 1280, y: 720))

        XCTAssertEqual(ax.x, 1280, accuracy: 0.001)
        // axY = 1440 - 720 = 720 — center of screen
        XCTAssertEqual(ax.y, 720, accuracy: 0.001)
    }

    // MARK: - Seam edge test

    /// Point on the exact boundary between two screens (x = 1440).
    /// The converter doesn't need to determine which screen the point
    /// is on — the formula only depends on primaryMaxY, which is global.
    /// This test locks in deterministic behavior: x=1440 produces a
    /// valid AX point regardless of which screen "owns" it.
    func testSeamEdge_deterministicResult() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let converter = CoordinateConverter(screenFrames: [primary, secondary])

        // Point exactly at seam: x=1440, y=450 in NSEvent coords.
        let ax = converter.toAX(CGPoint(x: 1440, y: 450))

        // X is unchanged.
        XCTAssertEqual(ax.x, 1440, accuracy: 0.001)
        // axY = 900 - 450 = 450. Deterministic regardless of screen.
        XCTAssertEqual(ax.y, 450, accuracy: 0.001)
    }

    // MARK: - Empty screens fallback

    /// If no screens are provided (shouldn't happen in practice),
    /// the converter returns the point unchanged as a safe fallback.
    func testNoScreens_identityFallback() {
        let converter = CoordinateConverter(screenFrames: [])

        let ax = converter.toAX(CGPoint(x: 100, y: 200))

        XCTAssertEqual(ax.x, 100, accuracy: 0.001)
        XCTAssertEqual(ax.y, 200, accuracy: 0.001)
    }

    // MARK: - No primary screen fallback

    /// If no screen has origin (0, 0), the converter falls back to
    /// the tallest screen's maxY for the flip.
    func testNoPrimaryScreen_fallsBackToTallest() {
        let screenA = CGRect(x: 100, y: 100, width: 1920, height: 1080)
        let screenB = CGRect(x: 2020, y: 100, width: 1440, height: 900)
        let converter = CoordinateConverter(screenFrames: [screenA, screenB])

        let ax = converter.toAX(CGPoint(x: 500, y: 300))

        XCTAssertEqual(ax.x, 500, accuracy: 0.001)
        // tallest maxY = 100 + 1080 = 1180; axY = 1180 - 300 = 880
        XCTAssertEqual(ax.y, 880, accuracy: 0.001)
    }
}
