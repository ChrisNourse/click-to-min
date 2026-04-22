import Foundation

// ClickDebouncer is a `final class` (not a struct) because the coordinator
// holds a single shared instance and mutates it from the click closure.
// Reference semantics make the single-owner invariant explicit — there's
// no risk of accidentally copying stale timestamp state into a captured
// struct value.

/// Per-item click debouncer keyed by bundle URL string.
///
/// Rapid trackpad double-taps can fire ~200ms apart, so the default
/// 300ms window is the conservative floor. Tune to 250ms if deliberate
/// minimize-then-restore feels sluggish.
public final class ClickDebouncer {
    /// Default debounce window. Named constant so callers and tests can
    /// reference it without magic numbers.
    public static let debounceInterval: TimeInterval = 0.3

    public let window: TimeInterval
    public let now: () -> Date

    /// Stores the last-allowed timestamp per item ID (bundle URL string).
    private var lastAllowed: [String: Date] = [:]

    public init(window: TimeInterval = ClickDebouncer.debounceInterval,
                now: @escaping () -> Date = { Date() }) {
        self.window = window
        self.now = now
    }

    /// Returns `true` if the click should proceed (not debounced).
    ///
    /// `itemID` is the **bundle URL string** (not PID) so app relaunches
    /// don't bypass the debounce window.
    ///
    /// Boundary behavior: a click arriving at *exactly* `window` seconds
    /// after the last allowed click is **allowed** (strictly greater-than
    /// comparison). This is deterministic and testable.
    public func shouldAllow(itemID: String) -> Bool {
        let current = now()
        if let last = lastAllowed[itemID] {
            let elapsed = current.timeIntervalSince(last)
            if elapsed < window {
                return false
            }
        }
        lastAllowed[itemID] = current
        return true
    }
}
