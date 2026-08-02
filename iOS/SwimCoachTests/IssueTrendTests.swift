import XCTest
@testable import SwimCoach

final class IssueTrendTests: XCTestCase {

    func testTooFewSessionsIsFlat() {
        XCTAssertEqual(IssueTrend.trend(occurrences: [true, true, false, true, true]), .flat)
    }

    func testFadingFaultIsImproving() {
        // Present in all early sessions, gone recently
        XCTAssertEqual(
            IssueTrend.trend(occurrences: [true, true, true, true, false, false, false, false]),
            .improving)
    }

    func testEmergingFaultIsWorsening() {
        XCTAssertEqual(
            IssueTrend.trend(occurrences: [false, false, false, false, true, true, true, true]),
            .worsening)
    }

    func testPersistentFaultIsFlat() {
        XCTAssertEqual(
            IssueTrend.trend(occurrences: [Bool](repeating: true, count: 10)), .flat)
    }

    func testSmallShiftBelowThresholdIsFlat() {
        // 3/5 earlier vs 2/5 recent = -0.2 delta, below the 0.25 threshold
        XCTAssertEqual(
            IssueTrend.trend(occurrences: [true, true, true, false, false,
                                           true, false, true, false, false]),
            .flat)
    }
}
