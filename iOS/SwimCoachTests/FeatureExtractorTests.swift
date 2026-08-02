import XCTest
import CoreML
@testable import SwimCoach

// Note: VNHumanBodyPoseObservation cannot be constructed without a live Vision request,
// so tensor-content tests requiring observations are skipped here.
// Those paths are validated end-to-end in the demo mode and real analysis flow.
final class FeatureExtractorTests: XCTestCase {

    // MARK: - Constants

    func testNJointsIs13() { XCTAssertEqual(FeatureExtractor.nJoints, 13) }
    func testNCoordsIs3()  { XCTAssertEqual(FeatureExtractor.nCoords, 3) }
    func testTargetLenIs90() { XCTAssertEqual(FeatureExtractor.targetLen, 90) }

    func testJointsCountMatchesNJoints() {
        XCTAssertEqual(FeatureExtractor.joints.count, FeatureExtractor.nJoints)
    }

    func testOutputTensorShapeConstants() {
        let channels = FeatureExtractor.nJoints * FeatureExtractor.nCoords
        XCTAssertEqual(channels, 39) // 13 joints × 3 coords
        XCTAssertEqual(channels * FeatureExtractor.targetLen, 3510) // 39 × 90
    }

    // MARK: - Nil guard on empty input

    func testReturnsNilForEmptyInput() {
        XCTAssertNil(FeatureExtractor.extractWindows(
            from: [PoseAnalyzer.TimedObservation](), effectiveFPS: 10))
    }

    // MARK: - Slot assignment (uniform time grid with gap zero-fill)

    func testUniformTimesMapOneToOne() {
        let times = (0..<30).map { Double($0) / 10.0 }   // 10 fps, no gaps
        let slots = FeatureExtractor.slotAssignments(times: times, fps: 10)
        XCTAssertEqual(slots.count, 30)
        XCTAssertEqual(slots.compactMap { $0 }, Array(0..<30))
    }

    func testDetectionGapProducesNilSlots() {
        // 1s of detections, 2s gap, 1s of detections at 10 fps
        let before: [Double] = (0..<10).map { Double($0) / 10.0 }
        let after: [Double] = (0..<10).map { 3.0 + Double($0) / 10.0 }
        let times: [Double] = before + after
        let slots = FeatureExtractor.slotAssignments(times: times, fps: 10)
        XCTAssertEqual(slots.count, 40)                 // spans 4s of real time
        let gapSlots = slots[12..<28]
        XCTAssertTrue(gapSlots.allSatisfy { $0 == nil }, "gap must zero-fill, not compress")
    }

    func testEmptyTimesEmptySlots() {
        XCTAssertTrue(FeatureExtractor.slotAssignments(times: [], fps: 10).isEmpty)
    }

    // MARK: - Window length (3 s in the pipeline's effective frame rate)

    func testWindowLengthAt10FPS() {
        XCTAssertEqual(FeatureExtractor.windowLength(for: 10), 30)
    }

    func testWindowLengthAt30FPS() {
        XCTAssertEqual(FeatureExtractor.windowLength(for: 30), 90)
    }

    func testWindowLengthFloorsAtMinObservations() {
        XCTAssertEqual(FeatureExtractor.windowLength(for: 0.5),
                       FeatureExtractor.minObservations)
    }

    // MARK: - Window ranges

    func testShortClipYieldsSingleWholeClipWindow() {
        let ranges = FeatureExtractor.windowRanges(frameCount: 20, windowLen: 30)
        XCTAssertEqual(ranges, [0..<20])
    }

    func testExactWindowLengthYieldsSingleWindow() {
        let ranges = FeatureExtractor.windowRanges(frameCount: 30, windowLen: 30)
        XCTAssertEqual(ranges, [0..<30])
    }

    func testWindowsSlideWithHalfOverlap() {
        let ranges = FeatureExtractor.windowRanges(frameCount: 90, windowLen: 30)
        XCTAssertEqual(ranges.map(\.lowerBound), [0, 15, 30, 45, 60])
        XCTAssertTrue(ranges.allSatisfy { $0.count == 30 })
    }

    func testFinalWindowIsFlushWithClipEnd() {
        let ranges = FeatureExtractor.windowRanges(frameCount: 100, windowLen: 30)
        XCTAssertEqual(ranges.last, 70..<100)
        XCTAssertTrue(ranges.allSatisfy { $0.count == 30 })
    }

    func testWindowsCoverEveryFrame() {
        let ranges = FeatureExtractor.windowRanges(frameCount: 137, windowLen: 30)
        var covered = Set<Int>()
        for r in ranges { covered.formUnion(r) }
        XCTAssertEqual(covered.count, 137)
    }
}
