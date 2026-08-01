import XCTest
@testable import SwimCoach

final class BiomechanicsEngineTests: XCTestCase {

    // MARK: - score(from:)

    func testPerfectScoreWithNoIssues() {
        XCTAssertEqual(BiomechanicsEngine.score(from: []), 100)
    }

    func testMajorIssueDeducts25() {
        let issue = makeIssue(severity: .major)
        XCTAssertEqual(BiomechanicsEngine.score(from: [issue]), 75)
    }

    func testModerateIssueDeducts15() {
        let issue = makeIssue(severity: .moderate)
        XCTAssertEqual(BiomechanicsEngine.score(from: [issue]), 85)
    }

    func testMinorIssueDeducts5() {
        let issue = makeIssue(severity: .minor)
        XCTAssertEqual(BiomechanicsEngine.score(from: [issue]), 95)
    }

    func testScoreClampedAt0() {
        let issues = (0..<10).map { _ in makeIssue(severity: .major) } // 200 pts deduction
        XCTAssertEqual(BiomechanicsEngine.score(from: issues), 0)
    }

    func testMixedSeverities() {
        let issues = [makeIssue(severity: .major), makeIssue(severity: .moderate), makeIssue(severity: .minor)]
        // 25 + 15 + 5 = 45 → score 55
        XCTAssertEqual(BiomechanicsEngine.score(from: issues), 55)
    }

    // MARK: - grade(from:)

    func testGradeA() { XCTAssertEqual(BiomechanicsEngine.grade(from: 90), "A") }
    func testGradeABoundary() { XCTAssertEqual(BiomechanicsEngine.grade(from: 100), "A") }
    func testGradeB() { XCTAssertEqual(BiomechanicsEngine.grade(from: 85), "B") }
    func testGradeBLowerBound() { XCTAssertEqual(BiomechanicsEngine.grade(from: 80), "B") }
    func testGradeC() { XCTAssertEqual(BiomechanicsEngine.grade(from: 75), "C") }
    func testGradeCLowerBound() { XCTAssertEqual(BiomechanicsEngine.grade(from: 70), "C") }
    func testGradeD() { XCTAssertEqual(BiomechanicsEngine.grade(from: 65), "D") }
    func testGradeDLowerBound() { XCTAssertEqual(BiomechanicsEngine.grade(from: 60), "D") }
    func testGradeF() { XCTAssertEqual(BiomechanicsEngine.grade(from: 59), "F") }
    func testGradeFAtZero() { XCTAssertEqual(BiomechanicsEngine.grade(from: 0), "F") }

    // MARK: - Helpers

    private func makeIssue(severity: TechniqueIssue.Severity) -> TechniqueIssue {
        TechniqueIssue(
            name: "test_issue",
            displayName: "Test Issue",
            severity: severity,
            observedValue: 0.5,
            threshold: 0.45,
            description: "Test description.",
            tip: "Test tip."
        )
    }
}
