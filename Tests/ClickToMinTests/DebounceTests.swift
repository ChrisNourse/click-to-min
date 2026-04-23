import XCTest
@testable import ClickToMinCore

final class DebounceTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a debouncer with a controllable clock starting at `Date.distantPast`.
    /// Returns the debouncer and a closure to advance time by the given interval.
    private func makeDebouncerWithClock(
        window: TimeInterval = ClickDebouncer.debounceInterval
    ) -> (debouncer: ClickDebouncer, advance: (TimeInterval) -> Void) {
        var current = Date(timeIntervalSinceReferenceDate: 0)
        let debouncer = ClickDebouncer(window: window) { current }
        let advance: (TimeInterval) -> Void = { interval in
            current = current.addingTimeInterval(interval)
        }
        return (debouncer, advance)
    }

    // MARK: - Basic behavior

    func testFirstClickAlwaysAllowed() {
        let (debouncer, _) = makeDebouncerWithClock()
        XCTAssertTrue(debouncer.shouldAllow(itemID: "com.apple.Safari"))
    }

    /// Same item within 300ms → suppressed.
    func testSameItemWithinWindow_suppressed() {
        let (debouncer, advance) = makeDebouncerWithClock()

        XCTAssertTrue(debouncer.shouldAllow(itemID: "com.apple.Safari"))
        advance(0.2) // 200ms < 300ms
        XCTAssertFalse(debouncer.shouldAllow(itemID: "com.apple.Safari"))
    }

    /// Same item after 300ms → allowed.
    func testSameItemAfterWindow_allowed() {
        let (debouncer, advance) = makeDebouncerWithClock()

        XCTAssertTrue(debouncer.shouldAllow(itemID: "com.apple.Safari"))
        advance(0.35) // 350ms > 300ms
        XCTAssertTrue(debouncer.shouldAllow(itemID: "com.apple.Safari"))
    }

    /// Different item within 300ms → allowed (per-item, not global).
    func testDifferentItemWithinWindow_allowed() {
        let (debouncer, advance) = makeDebouncerWithClock()

        XCTAssertTrue(debouncer.shouldAllow(itemID: "com.apple.Safari"))
        advance(0.1) // 100ms
        // Different item — should not be debounced.
        XCTAssertTrue(debouncer.shouldAllow(itemID: "com.apple.TextEdit"))
    }

    // MARK: - Boundary at exactly 300ms

    /// Click arriving at *exactly* `window` seconds after the last allowed
    /// click is **allowed** (elapsed >= window, using strict < for suppress).
    /// This is deterministic and documented in ClickDebouncer.shouldAllow.
    func testExactBoundary_allowed() {
        let (debouncer, advance) = makeDebouncerWithClock()

        XCTAssertTrue(debouncer.shouldAllow(itemID: "com.apple.Safari"))
        advance(0.3) // exactly 300ms
        // elapsed (0.3) is NOT < window (0.3), so allowed.
        XCTAssertTrue(debouncer.shouldAllow(itemID: "com.apple.Safari"))
    }

    /// One nanosecond before the boundary → suppressed.
    func testJustBeforeBoundary_suppressed() {
        let (debouncer, advance) = makeDebouncerWithClock()

        XCTAssertTrue(debouncer.shouldAllow(itemID: "com.apple.Safari"))
        advance(0.2999999) // just under 300ms
        XCTAssertFalse(debouncer.shouldAllow(itemID: "com.apple.Safari"))
    }

    // MARK: - Injected clock verification

    /// The debouncer must use the injected clock, not `Date()`.
    /// We verify by checking that time only advances when we say it does.
    func testInjectedClock_noWallClockDependency() {
        let (debouncer, advance) = makeDebouncerWithClock()

        XCTAssertTrue(debouncer.shouldAllow(itemID: "x"))
        // Without advancing the clock, a second call should be suppressed
        // even if wall-clock time has passed.
        XCTAssertFalse(debouncer.shouldAllow(itemID: "x"))

        // Now advance past the window.
        advance(1.0)
        XCTAssertTrue(debouncer.shouldAllow(itemID: "x"))
    }

    // MARK: - debounceInterval constant

    func testDebounceIntervalConstant() {
        XCTAssertEqual(ClickDebouncer.debounceInterval, 0.3, accuracy: 0.0001)
    }

    // MARK: - Suppressed click doesn't reset the timer

    /// A suppressed click should NOT update the last-allowed timestamp.
    /// This means the window is measured from the last *allowed* click,
    /// not the last *attempted* click.
    func testSuppressedClickDoesNotResetTimer() {
        let (debouncer, advance) = makeDebouncerWithClock()

        XCTAssertTrue(debouncer.shouldAllow(itemID: "x"))  // t=0, allowed
        advance(0.2)
        XCTAssertFalse(debouncer.shouldAllow(itemID: "x")) // t=0.2, suppressed
        advance(0.15) // total t=0.35, which is 0.35 from last ALLOWED (t=0)
        XCTAssertTrue(debouncer.shouldAllow(itemID: "x"))  // elapsed from t=0 = 0.35 > 0.3
    }

    // MARK: - Default init (real clock)

    /// Exercises the default `now: { Date() }` parameter so the default
    /// closure is covered.
    func testDefaultInit_firstClickAllowed() {
        let debouncer = ClickDebouncer()
        XCTAssertTrue(debouncer.shouldAllow(itemID: "default-init-test"))
    }

    // MARK: - Multiple items independent

    func testMultipleItemsIndependent() {
        let (debouncer, advance) = makeDebouncerWithClock()

        XCTAssertTrue(debouncer.shouldAllow(itemID: "A"))
        XCTAssertTrue(debouncer.shouldAllow(itemID: "B"))

        advance(0.2)
        // Both within window — both suppressed.
        XCTAssertFalse(debouncer.shouldAllow(itemID: "A"))
        XCTAssertFalse(debouncer.shouldAllow(itemID: "B"))

        advance(0.15) // total 0.35 from last allowed
        // Both past window — both allowed.
        XCTAssertTrue(debouncer.shouldAllow(itemID: "A"))
        XCTAssertTrue(debouncer.shouldAllow(itemID: "B"))
    }
}
