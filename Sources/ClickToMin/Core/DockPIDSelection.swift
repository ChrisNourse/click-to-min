import Foundation

/// Lightweight value describing a candidate Dock process, decoupled from
/// `NSRunningApplication` so Core stays free of AppKit imports.
public struct DockProcessCandidate {
    public let processIdentifier: pid_t
    public let isTerminated: Bool
    public let launchDate: Date?

    public init(processIdentifier: pid_t, isTerminated: Bool, launchDate: Date?) {
        self.processIdentifier = processIdentifier
        self.isTerminated = isTerminated
        self.launchDate = launchDate
    }
}

/// Selects the best Dock process from a list of candidates.
///
/// Tie-break rules (during Dock relaunch, both old and new instances
/// can appear transiently):
///   1. Never select a terminated instance.
///   2. Prefer the instance with the latest `launchDate`.
///   3. If `launchDate` is nil for one, prefer the non-nil.
///   4. Both nil → arbitrary stable order.
public func selectBestDockProcess(_ candidates: [DockProcessCandidate]) -> pid_t? {
    candidates
        .filter { !$0.isTerminated }
        .max { lhs, rhs in
            switch (lhs.launchDate, rhs.launchDate) {
            case (nil, .some):
                true // prefer rhs (non-nil date)
            case (.some, nil):
                false // prefer lhs (non-nil date)
            case let (.some(dateA), .some(dateB)):
                dateA < dateB // prefer later date
            case (nil, nil):
                false // arbitrary stable order
            }
        }?.processIdentifier
}
