import XCTest
@testable import SwimCoach

final class FeedbackEngineTests: XCTestCase {

    // All zeros → no issues (all below threshold 0.45)
    func testZeroProbabilitiesProducesNoIssues() {
        let probs = [Float](repeating: 0, count: 10)
        XCTAssertTrue(FeedbackEngine.decode(probabilities: probs).isEmpty)
    }

    // Probability exactly at threshold → not included (strictly >=)
    func testExactlyAtThresholdIsIncluded() {
        var probs = [Float](repeating: 0, count: 10)
        probs[0] = 0.45 // left_elbow_overextension
        let issues = FeedbackEngine.decode(probabilities: probs)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].name, "left_elbow_overextension")
    }

    // Just below threshold → excluded
    func testBelowThresholdExcluded() {
        var probs = [Float](repeating: 0, count: 10)
        probs[0] = 0.44
        XCTAssertTrue(FeedbackEngine.decode(probabilities: probs).isEmpty)
    }

    // Index 6 = body_sag; prob 0.9 → base severity is .major → stays .major (>0.8 escalation)
    func testBodySagHighProbIsMajor() {
        var probs = [Float](repeating: 0, count: 10)
        probs[6] = 0.9 // body_sag
        let issues = FeedbackEngine.decode(probabilities: probs)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].name, "body_sag")
        XCTAssertEqual(issues[0].severity, .major)
    }

    // Index 4 = left_knee_overbend; base severity .minor, prob 0.9 → escalates to .moderate
    func testMinorEscalatesToModerateAbove0_8() {
        var probs = [Float](repeating: 0, count: 10)
        probs[4] = 0.9 // left_knee_overbend (.minor base)
        let issues = FeedbackEngine.decode(probabilities: probs)
        XCTAssertEqual(issues[0].severity, .moderate)
    }

    // Index 4 = left_knee_overbend; base severity .minor, prob 0.6 → stays .minor
    func testMinorStaysMinorBelow0_8() {
        var probs = [Float](repeating: 0, count: 10)
        probs[4] = 0.6 // left_knee_overbend (.minor base)
        let issues = FeedbackEngine.decode(probabilities: probs)
        XCTAssertEqual(issues[0].severity, .minor)
    }

    // All 1.0 → 10 issues, all names present
    func testAllMaxProbProducesAllIssues() {
        let probs = [Float](repeating: 1.0, count: 10)
        let issues = FeedbackEngine.decode(probabilities: probs)
        XCTAssertEqual(issues.count, 10)
    }

    // Extra probabilities beyond catalog size are silently ignored
    func testExtraProbabilitiesIgnored() {
        let probs = [Float](repeating: 1.0, count: 15)
        let issues = FeedbackEngine.decode(probabilities: probs)
        XCTAssertEqual(issues.count, 10)
    }

    // Empty input → no issues
    func testEmptyInputProducesNoIssues() {
        XCTAssertTrue(FeedbackEngine.decode(probabilities: []).isEmpty)
    }

    // observedValue should match the probability passed in
    func testObservedValueMatchesProbability() {
        var probs = [Float](repeating: 0, count: 10)
        probs[7] = 0.73 // stroke_asymmetry
        let issues = FeedbackEngine.decode(probabilities: probs)
        XCTAssertEqual(issues[0].observedValue, Double(0.73), accuracy: 0.001)
    }
}
