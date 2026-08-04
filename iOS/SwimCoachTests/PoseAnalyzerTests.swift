import XCTest
@testable import SwimCoach

/// Tests the pure candidate-selection seam of `PoseAnalyzer`.
///
/// `VNHumanBodyPoseObservation` cannot be constructed with chosen joint
/// confidences, so the Vision-facing frame loop is not directly testable.
/// Only three values decide which observation a frame keeps — the torso align
/// angle, the torso length and the shoulder confidence — and all three are
/// lifted into `PoseAnalyzer.PoseCandidate`, which is what these tests drive.
final class PoseAnalyzerTests: XCTestCase {

    /// `torso: nil` is the unmeasurable case (hips under the waterline), which
    /// the size gate accepts — so existing angle-only cases keep their meaning.
    private func candidate(_ alignAngle: Float?,
                           _ shoulderConfidence: Float = 0.5,
                           torso: Float? = nil) -> PoseAnalyzer.PoseCandidate {
        PoseAnalyzer.PoseCandidate(alignAngle: alignAngle,
                                   torsoLength: torso,
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

    // MARK: - Size gate (parity with MIN/MAX_MEDIAN_TORSO in ml/analysis/gating.py)

    /// The contract itself, pinned on the iOS side too. The cross-language
    /// guard lives in ml/tests/test_torso_gate_parity.py; this keeps a
    /// Swift-only edit from looking harmless in review.
    func testTorsoBoundsMatchThePythonGate() {
        XCTAssertEqual(PoseAnalyzer.minTorsoLength, 0.09,
                       "Must equal MIN_MEDIAN_TORSO in ml/analysis/gating.py")
        XCTAssertEqual(PoseAnalyzer.maxTorsoLength, 0.60,
                       "Must equal MAX_MEDIAN_TORSO in ml/analysis/gating.py")
    }

    func testTooSmallCandidateIsRejected() {
        // Arrange — far-field race footage measured 0.084 in the Python gate
        let candidates = [candidate(10, 0.9, torso: 0.084)]

        // Act
        let best = PoseAnalyzer.bestCandidateIndex(candidates)

        // Assert
        XCTAssertNil(best)
    }

    func testCandidateExactlyAtTheMinimumIsAccepted() {
        // Arrange — the bound is inclusive: under-reject rather than over-reject
        let candidates = [candidate(10, 0.9, torso: PoseAnalyzer.minTorsoLength)]

        // Act
        let best = PoseAnalyzer.bestCandidateIndex(candidates)

        // Assert
        XCTAssertEqual(best, 0)
    }

    func testCandidateAboveTheMinimumIsAccepted() {
        // Arrange — legitimate 3–6 m footage measures 0.095–0.19
        let candidates = [candidate(10, 0.9, torso: 0.14)]

        // Act
        let best = PoseAnalyzer.bestCandidateIndex(candidates)

        // Assert
        XCTAssertEqual(best, 0)
    }

    func testImplausiblyLargeCandidateIsRejected() {
        // Arrange — crowd shot, detector stitching two people into one body
        let candidates = [candidate(5, 0.9, torso: 1.06)]

        // Act
        let best = PoseAnalyzer.bestCandidateIndex(candidates)

        // Assert
        XCTAssertNil(best)
    }

    func testCandidateExactlyAtTheMaximumIsAccepted() {
        // Arrange
        let candidates = [candidate(5, 0.9, torso: PoseAnalyzer.maxTorsoLength)]

        // Act
        let best = PoseAnalyzer.bestCandidateIndex(candidates)

        // Assert
        XCTAssertEqual(best, 0)
    }

    /// Vision gives no usable location for an unconfident joint, so an
    /// unmeasurable torso must never be read as "too small".
    func testUnmeasurableTorsoIsAccepted() {
        // Arrange — hips under the waterline: no angle, no size
        let candidates = [candidate(nil, 0.55, torso: nil)]

        // Act
        let best = PoseAnalyzer.bestCandidateIndex(candidates)

        // Assert
        XCTAssertEqual(best, 0)
    }

    // MARK: - Size gate × horizontal filter

    /// Size is a filter, not a ranking term: a flatter but too-small bystander
    /// must not outrank the full-size swimmer the way it would on angle alone.
    func testFullSizeSwimmerBeatsFlatterButTooSmallBystander() {
        // Arrange
        let candidates = [candidate(2, 0.9, torso: 0.03), candidate(35, 0.5, torso: 0.15)]

        // Act
        let best = PoseAnalyzer.bestCandidateIndex(candidates)

        // Assert
        XCTAssertEqual(best, 1)
    }

    /// Both filters must pass. Neither an upright full-size person nor a
    /// horizontal too-small one is the swimmer.
    func testUprightFullSizeAndHorizontalTooSmallBothFail() {
        // Arrange
        let candidates = [candidate(88, 0.9, torso: 0.16), candidate(8, 0.9, torso: 0.02)]

        // Act
        let best = PoseAnalyzer.bestCandidateIndex(candidates)

        // Assert
        XCTAssertNil(best)
    }

    /// The frame is dropped, not handed to the least-bad candidate — the clip
    /// then falls through to the existing "no swimmer" / "too few frames" guards.
    func testFrameOfOnlyTooSmallCandidatesIsDropped() {
        // Arrange — a distant cluster of bystanders, all plausibly horizontal
        let candidates = [candidate(10, 0.9, torso: 0.05),
                          candidate(nil, 0.8, torso: 0.06),
                          candidate(170, 0.7, torso: 0.088)]

        // Act
        let best = PoseAnalyzer.bestCandidateIndex(candidates)

        // Assert
        XCTAssertNil(best)
    }

    /// Size filtering happens before the confidence tie-break, so a crowded
    /// frame still resolves to the same swimmer whatever order Vision reports.
    func testSizeFilteringIsOrderIndependent() {
        // Arrange
        let candidates = [candidate(nil, 0.95, torso: 0.04),
                          candidate(nil, 0.60, torso: 0.12),
                          candidate(nil, 0.40, torso: 0.11)]

        // Act
        let best = PoseAnalyzer.bestCandidateIndex(candidates)
        let bestReversed = PoseAnalyzer.bestCandidateIndex(Array(candidates.reversed()))

        // Assert — the 0.60-confidence, full-size swimmer wins from either ordering
        XCTAssertEqual(best, 1)
        XCTAssertEqual(bestReversed, 1)
    }
}
