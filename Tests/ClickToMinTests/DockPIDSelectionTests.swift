import Foundation
import XCTest

@testable import ClickToMinCore

final class DockPIDSelectionTests: XCTestCase {

    // MARK: - Empty / all terminated

    func testEmptyCandidates_returnsNil() {
        XCTAssertNil(selectBestDockProcess([]))
    }

    func testAllTerminated_returnsNil() {
        let candidates = [
            DockProcessCandidate(processIdentifier: 10, isTerminated: true, launchDate: Date()),
            DockProcessCandidate(processIdentifier: 20, isTerminated: true, launchDate: Date()),
        ]
        XCTAssertNil(selectBestDockProcess(candidates))
    }

    // MARK: - Single candidate

    func testSingleLive_returnsThatPID() {
        let candidates = [
            DockProcessCandidate(processIdentifier: 42, isTerminated: false, launchDate: Date()),
        ]
        XCTAssertEqual(selectBestDockProcess(candidates), 42)
    }

    func testSingleTerminated_returnsNil() {
        let candidates = [
            DockProcessCandidate(processIdentifier: 42, isTerminated: true, launchDate: Date()),
        ]
        XCTAssertNil(selectBestDockProcess(candidates))
    }

    // MARK: - Tie-break: prefer latest launchDate

    func testTwoCandidates_prefersLaterLaunchDate() {
        let early = Date(timeIntervalSinceReferenceDate: 1000)
        let late = Date(timeIntervalSinceReferenceDate: 2000)
        let candidates = [
            DockProcessCandidate(processIdentifier: 10, isTerminated: false, launchDate: early),
            DockProcessCandidate(processIdentifier: 20, isTerminated: false, launchDate: late),
        ]
        XCTAssertEqual(selectBestDockProcess(candidates), 20)
    }

    func testTwoCandidates_laterDateFirstInArray_stillPreferred() {
        let early = Date(timeIntervalSinceReferenceDate: 1000)
        let late = Date(timeIntervalSinceReferenceDate: 2000)
        let candidates = [
            DockProcessCandidate(processIdentifier: 20, isTerminated: false, launchDate: late),
            DockProcessCandidate(processIdentifier: 10, isTerminated: false, launchDate: early),
        ]
        XCTAssertEqual(selectBestDockProcess(candidates), 20)
    }

    // MARK: - Tie-break: nil vs non-nil launchDate

    func testNilDateVsNonNilDate_prefersNonNil() {
        let candidates = [
            DockProcessCandidate(processIdentifier: 10, isTerminated: false, launchDate: nil),
            DockProcessCandidate(processIdentifier: 20, isTerminated: false, launchDate: Date()),
        ]
        XCTAssertEqual(selectBestDockProcess(candidates), 20)
    }

    func testNonNilDateVsNilDate_prefersNonNil() {
        let candidates = [
            DockProcessCandidate(processIdentifier: 10, isTerminated: false, launchDate: Date()),
            DockProcessCandidate(processIdentifier: 20, isTerminated: false, launchDate: nil),
        ]
        XCTAssertEqual(selectBestDockProcess(candidates), 10)
    }

    // MARK: - Tie-break: both nil dates

    func testBothNilDates_returnsOne() {
        let candidates = [
            DockProcessCandidate(processIdentifier: 10, isTerminated: false, launchDate: nil),
            DockProcessCandidate(processIdentifier: 20, isTerminated: false, launchDate: nil),
        ]
        let result = selectBestDockProcess(candidates)
        XCTAssertNotNil(result)
    }

    // MARK: - Filters terminated before tie-break

    func testTerminatedWithLateDateFiltered() {
        let early = Date(timeIntervalSinceReferenceDate: 1000)
        let late = Date(timeIntervalSinceReferenceDate: 9000)
        let candidates = [
            DockProcessCandidate(processIdentifier: 10, isTerminated: false, launchDate: early),
            DockProcessCandidate(processIdentifier: 20, isTerminated: true, launchDate: late),
        ]
        XCTAssertEqual(selectBestDockProcess(candidates), 10,
                       "terminated candidate with later date must not win")
    }

    // MARK: - Three candidates

    func testThreeCandidates_mixedStates() {
        let early = Date(timeIntervalSinceReferenceDate: 1000)
        let mid = Date(timeIntervalSinceReferenceDate: 2000)
        let late = Date(timeIntervalSinceReferenceDate: 3000)
        let candidates = [
            DockProcessCandidate(processIdentifier: 10, isTerminated: false, launchDate: early),
            DockProcessCandidate(processIdentifier: 20, isTerminated: true, launchDate: late),
            DockProcessCandidate(processIdentifier: 30, isTerminated: false, launchDate: mid),
        ]
        XCTAssertEqual(selectBestDockProcess(candidates), 30,
                       "latest non-terminated candidate should win")
    }

    func testSingleLiveWithNilDate_returnsIt() {
        let candidates = [
            DockProcessCandidate(processIdentifier: 55, isTerminated: false, launchDate: nil),
        ]
        XCTAssertEqual(selectBestDockProcess(candidates), 55)
    }
}
