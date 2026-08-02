import XCTest
@testable import SwimCoach

final class SessionComparisonTests: XCTestCase {

    private func result(score: Int, issues: [(String, Double)]) -> AnalysisResult {
        AnalysisResult(
            id: UUID(), score: score, grade: "C",
            strokeCount: 10, kickRatePerMin: 40, strokeAsymmetry: 0.1,
            frameCount: 100, sampledFrames: 100, fps: 30,
            issues: issues.map {
                TechniqueIssue(name: $0.0, displayName: $0.0, severity: .moderate,
                               observedValue: $0.1, threshold: 0.45,
                               description: "", tip: "")
            },
            tips: [], analyzedAt: Date()
        )
    }

    func testNewAndResolved() {
        let earlier = result(score: 60, issues: [("body_sag", 0.8)])
        let later = result(score: 70, issues: [("low_kick_rate", 0.6)])
        let deltas = SessionComparison.issueDeltas(from: earlier, to: later)
        XCTAssertEqual(deltas.first { $0.name == "body_sag" }?.verdict, .resolved)
        XCTAssertEqual(deltas.first { $0.name == "low_kick_rate" }?.verdict, .new)
    }

    func testImprovedWorsenedUnchanged() {
        let earlier = result(score: 60, issues: [
            ("a", 0.80), ("b", 0.50), ("c", 0.60)])
        let later = result(score: 65, issues: [
            ("a", 0.55), ("b", 0.75), ("c", 0.65)])
        let deltas = SessionComparison.issueDeltas(from: earlier, to: later)
        XCTAssertEqual(deltas.first { $0.name == "a" }?.verdict, .improved)
        XCTAssertEqual(deltas.first { $0.name == "b" }?.verdict, .worsened)
        XCTAssertEqual(deltas.first { $0.name == "c" }?.verdict, .unchanged)  // +0.05 < threshold
    }

    func testOrderingPutsWorsenedAndNewFirst() {
        let earlier = result(score: 60, issues: [("resolved_one", 0.8), ("worse_one", 0.5)])
        let later = result(score: 60, issues: [("worse_one", 0.9), ("new_one", 0.6)])
        let deltas = SessionComparison.issueDeltas(from: earlier, to: later)
        XCTAssertEqual(deltas.map(\.verdict).prefix(2), [.worsened, .new])
    }

    func testEmptyBothSides() {
        let deltas = SessionComparison.issueDeltas(
            from: result(score: 90, issues: []), to: result(score: 95, issues: []))
        XCTAssertTrue(deltas.isEmpty)
    }
}
