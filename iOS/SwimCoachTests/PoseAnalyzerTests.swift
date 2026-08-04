import XCTest
@testable import SwimCoach

/// Tests the pure candidate-selection seam of `PoseAnalyzer`.
///
/// `VNHumanBodyPoseObservation` cannot be constructed with chosen joint
/// confidences, so the Vision-facing frame loop is not directly testable.
/// Only two values decide which observation a frame keeps — the torso align
/// angle and the shoulder confidence — and both are lifted into
/// `PoseAnalyzer.PoseCandidate`, which is what these tests drive.
final class PoseAnalyzerTests: XCTestCase {

    private func candidate(_ alignAngle: Float?,
                           _ shoulderConfidence: Float = 0.5) -> PoseAnalyzer.PoseCandidate {
        PoseAnalyzer.PoseCandidate(alignAngle: alignAngle,
                                   shoulderConfidence: shoulderConfidence)
    }

    // Headline regression: the swimmer's hips are occluded (angle unknown, which
    // ranks as the vertical sentinel 90) while an upright bystander's hips are
    // visible at 85. Ranking before filtering handed the frame to the bystander
    // and then rejected it, throwing away the swimmer sitting in the same list.
    func testOccludedSwimmerBeatsUprightBystander() {
        // Arrange
        let candidates = [candidate(nil, 0.6), candidate(85, 0.9)]

        // Act
        let best = PoseAnalyzer.bestCandidateIndex(candidates)

        // Assert
        XCTAssertEqual(best, 0)
    }

    // A bystander at exactly 90 carries the same likelihood as the unknown-angle
    // sentinel. Filtering first drops it (90 is not horizontal), so the tie is
    // resolved among the eligible unknown-angle candidates by shoulder
    // confidence — never by Vision's arbitrary result ordering.
    func testUprightBystanderLosesTieAndConfidenceDecidesDeterministically() {
        // Arrange
        let candidates = [candidate(90, 0.95), candidate(nil, 0.40), candidate(nil, 0.80)]

        // Act
        let best = PoseAnalyzer.bestCandidateIndex(candidates)
        let bestReversed = PoseAnalyzer.bestCandidateIndex(Array(candidates.reversed()))

        // Assert — the 0.80 swimmer wins from either input ordering
        XCTAssertEqual(best, 2)
        XCTAssertEqual(bestReversed, 0)
    }

    func testPrefersFlattestHorizontalCandidate() {
        // Arrange
        let candidates = [candidate(20), candidate(40)]

        // Act
        let best = PoseAnalyzer.bestCandidateIndex(candidates)

        // Assert
        XCTAssertEqual(best, 0)
    }

    func testAllUprightCandidatesDropTheFrame() {
        // Arrange
        let candidates = [candidate(70), candidate(85)]

        // Act
        let best = PoseAnalyzer.bestCandidateIndex(candidates)

        // Assert
        XCTAssertNil(best)
    }

    func testEmptyCandidateListReturnsNil() {
        // Arrange
        let candidates: [PoseAnalyzer.PoseCandidate] = []

        // Act
        let best = PoseAnalyzer.bestCandidateIndex(candidates)

        // Assert
        XCTAssertNil(best)
    }

    func testSingleUnknownAngleCandidateIsSelected() {
        // Arrange — practice footage: one swimmer, hips below threshold
        let candidates = [candidate(nil, 0.55)]

        // Act
        let best = PoseAnalyzer.bestCandidateIndex(candidates)

        // Assert
        XCTAssertEqual(best, 0)
    }
}
