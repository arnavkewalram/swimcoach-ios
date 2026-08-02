import XCTest
@testable import SwimCoach

final class SessionFilterTests: XCTestCase {

    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(SessionFilter.matches(query: "", name: "", notes: "", dateText: ""))
        XCTAssertTrue(SessionFilter.matches(query: "   ", name: "x", notes: "", dateText: ""))
    }

    func testMatchesAnyFieldCaseInsensitively() {
        XCTAssertTrue(SessionFilter.matches(
            query: "threshold", name: "Threshold Tuesday", notes: "", dateText: ""))
        XCTAssertTrue(SessionFilter.matches(
            query: "CATCH", name: "", notes: "worked on catch", dateText: ""))
        XCTAssertTrue(SessionFilter.matches(
            query: "aug", name: "", notes: "", dateText: "Aug 1, 2026 at 9:00 PM"))
    }

    func testNonMatchingQuery() {
        XCTAssertFalse(SessionFilter.matches(
            query: "butterfly", name: "Threshold Tuesday", notes: "catch work", dateText: "Aug 1"))
    }

    func testGradeFilterEmptyMeansAll() {
        XCTAssertTrue(SessionFilter.matches(grades: [], grade: "C"))
        XCTAssertTrue(SessionFilter.matches(grades: ["C", "D"], grade: "C"))
        XCTAssertFalse(SessionFilter.matches(grades: ["A"], grade: "C"))
    }
}
