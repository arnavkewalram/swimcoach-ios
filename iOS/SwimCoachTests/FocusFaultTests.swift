import XCTest
@testable import SwimCoach

final class FocusFaultTests: XCTestCase {

    func testEmptyAndNonRecurringGiveNoFocus() {
        XCTAssertNil(FocusFault.pick(recentIssueNames: []))
        // Each fault appears once — one-offs are noise
        XCTAssertNil(FocusFault.pick(recentIssueNames: [["body_sag"], ["low_kick_rate"]]))
    }

    func testMostFrequentWins() {
        let sessions = [
            ["body_sag", "low_kick_rate"],
            ["body_sag"],
            ["body_sag", "stroke_asymmetry"],
            ["low_kick_rate"],
        ]
        XCTAssertEqual(FocusFault.pick(recentIssueNames: sessions), "body_sag")
    }

    func testWindowLimitsLookback() {
        // body_sag dominates old history; low_kick_rate rules the last 5
        let sessions = [["body_sag"], ["body_sag"], ["body_sag"], ["body_sag"]]
            + Array(repeating: ["low_kick_rate"], count: 5)
        XCTAssertEqual(FocusFault.pick(recentIssueNames: sessions), "low_kick_rate")
    }

    func testTieBreaksTowardMostRecent() {
        let sessions = [
            ["body_sag"], ["body_sag"],
            ["low_kick_rate"], ["low_kick_rate"],
        ]
        // Both appear twice; low_kick_rate seen more recently
        XCTAssertEqual(FocusFault.pick(recentIssueNames: sessions), "low_kick_rate")
    }

    func testOccurrenceCounting() {
        let sessions = [["body_sag"], [], ["body_sag"], ["low_kick_rate"]]
        XCTAssertEqual(FocusFault.occurrences(of: "body_sag", in: sessions), 2)
        XCTAssertEqual(FocusFault.occurrences(of: "stroke_asymmetry", in: sessions), 0)
    }

    func testDuplicateNamesInOneSessionCountOnce() {
        let sessions = [["body_sag", "body_sag"], ["low_kick_rate"]]
        XCTAssertNil(FocusFault.pick(recentIssueNames: sessions),
                     "duplicates within a session must not fake recurrence")
    }
}
