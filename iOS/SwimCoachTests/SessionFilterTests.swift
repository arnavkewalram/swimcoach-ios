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

    func testSwimmerFilterSemantics() {
        XCTAssertTrue(SessionFilter.matches(swimmers: [], swimmer: ""))
        XCTAssertTrue(SessionFilter.matches(swimmers: [], swimmer: "Maya"))
        XCTAssertTrue(SessionFilter.matches(swimmers: ["Maya"], swimmer: "Maya"))
        XCTAssertFalse(SessionFilter.matches(swimmers: ["Maya"], swimmer: "Arnav"))
        XCTAssertFalse(SessionFilter.matches(swimmers: ["Maya"], swimmer: ""),
                       "a selection hides untagged sessions")
    }

    func testSearchIncludesSwimmer() {
        XCTAssertTrue(SessionFilter.matches(
            query: "maya", name: "", notes: "", dateText: "", swimmer: "Maya"))
        XCTAssertFalse(SessionFilter.matches(
            query: "maya", name: "", notes: "", dateText: "", swimmer: "Arnav"))
        XCTAssertTrue(SessionFilter.matches(
            query: "", name: "", notes: "", dateText: "", swimmer: "Arnav"),
            "empty query still matches everything")
    }

    func testGradeFilterEmptyMeansAll() {
        XCTAssertTrue(SessionFilter.matches(grades: [], grade: "C"))
        XCTAssertTrue(SessionFilter.matches(grades: ["C", "D"], grade: "C"))
        XCTAssertFalse(SessionFilter.matches(grades: ["A"], grade: "C"))
    }
}
