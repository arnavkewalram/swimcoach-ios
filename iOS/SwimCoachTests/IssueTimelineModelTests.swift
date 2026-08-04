import XCTest
@testable import SwimCoach

final class IssueTimelineModelTests: XCTestCase {

    // Catalog label indices (pinned by IssueWindowTests):
    // left_elbow_collapse = 2 (moderate), body_sag = 6 (major),
    // low_kick_rate = 8 (minor).

    private func window(start: Double, end: Double,
                        probs: [Int: Float]) -> IssueWindow {
        var p = [Float](repeating: 0.1, count: 10)
        for (index, value) in probs { p[index] = value }
        return IssueWindow(start: start, end: end, probs: p)
    }

    private func issue(_ name: String,
                       _ severity: TechniqueIssue.Severity,
                       threshold: Double = 0.45) -> TechniqueIssue {
        TechniqueIssue(name: name, displayName: name, severity: severity,
                       observedValue: 0.9, threshold: threshold,
                       description: "", tip: "")
    }

    // MARK: - Normalization

    func testSingleWindowNormalizesToClipFraction() throws {
        // Arrange — the pipeline's first window always opens at the
        // detection origin (here 0); only the 3–6 window flags body_sag
        let windows = [window(start: 0, end: 3, probs: [6: 0.1]),
                       window(start: 3, end: 6, probs: [6: 0.9])]
        let issues = [issue("body_sag", .major)]

        // Act
        let model = try XCTUnwrap(IssueTimelineModel.make(
            windows: windows, issues: issues, durationSeconds: 12))

        // Assert
        XCTAssertEqual(model.segments.count, 1)
        let segment = try XCTUnwrap(model.segments.first)
        XCTAssertEqual(segment.startFraction, 0.25, accuracy: 1e-9)
        XCTAssertEqual(segment.endFraction, 0.50, accuracy: 1e-9)
        XCTAssertEqual(segment.severity, .major)
        XCTAssertEqual(segment.seekTime, 3, accuracy: 1e-9)
    }

    func testOverlappingWindowsOfSameIssueMergeIntoOneSegment() throws {
        // Arrange — sliding windows 0–3 and 1.5–4.5 both above threshold
        let windows = [window(start: 0, end: 3, probs: [6: 0.8]),
                       window(start: 1.5, end: 4.5, probs: [6: 0.9])]
        let issues = [issue("body_sag", .major)]

        // Act
        let model = try XCTUnwrap(IssueTimelineModel.make(
            windows: windows, issues: issues, durationSeconds: 9))

        // Assert — one merged run 0–4.5, seeking to its start
        XCTAssertEqual(model.segments.count, 1)
        let segment = try XCTUnwrap(model.segments.first)
        XCTAssertEqual(segment.startFraction, 0, accuracy: 1e-9)
        XCTAssertEqual(segment.endFraction, 0.5, accuracy: 1e-9)
        XCTAssertEqual(segment.seekTime, 0, accuracy: 1e-9)
    }

    // MARK: - Detected-span origin

    func testNonZeroOriginNormalizesRelativeToDetectionStart() throws {
        // Arrange — swimmer first detected at t=10s. Window times are
        // ABSOLUTE source-video time; `duration` is the LENGTH of the
        // detected span (10–22), not an end time.
        let windows = [window(start: 10, end: 13, probs: [6: 0.1]),
                       window(start: 13, end: 16, probs: [6: 0.9])]
        let issues = [issue("body_sag", .major)]

        // Act
        let model = try XCTUnwrap(IssueTimelineModel.make(
            windows: windows, issues: issues, durationSeconds: 12))

        // Assert — 13–16 sits a quarter into the 12s span, not off the bar
        XCTAssertEqual(model.segments.count, 1)
        let segment = try XCTUnwrap(model.segments.first)
        XCTAssertEqual(segment.startFraction, 0.25, accuracy: 1e-9)
        XCTAssertEqual(segment.endFraction, 0.50, accuracy: 1e-9)
        // Seek stays ABSOLUTE — it drives the real player timeline
        XCTAssertEqual(segment.seekTime, 13, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(model.seekTime(atFraction: 0.3)),
                       13, accuracy: 1e-9)
    }

    func testLateDetectionBeyondDurationStillRendersStrip() throws {
        // Arrange — detection starts at 20s and spans 10s. Clamping to
        // [0, duration] collapsed every window to zero width and hid the
        // whole strip; anchoring to the origin keeps it.
        let windows = [window(start: 20, end: 23, probs: [6: 0.9]),
                       window(start: 25, end: 28, probs: [6: 0.1])]
        let issues = [issue("body_sag", .major)]

        // Act
        let model = try XCTUnwrap(IssueTimelineModel.make(
            windows: windows, issues: issues, durationSeconds: 10))

        // Assert — 20–23 is the first 30% of the detected span
        XCTAssertEqual(model.segments.count, 1)
        let segment = try XCTUnwrap(model.segments.first)
        XCTAssertEqual(segment.startFraction, 0, accuracy: 1e-9)
        XCTAssertEqual(segment.endFraction, 0.3, accuracy: 1e-9)
        XCTAssertEqual(segment.seekTime, 20, accuracy: 1e-9)
    }

    func testZeroOriginGeometryIsUnchanged() throws {
        // Arrange — regression guard: clips detected from t=0 must produce
        // exactly the pre-fix segments, asserted segment-for-segment
        let windows = [window(start: 0, end: 3, probs: [6: 0.9]),
                       window(start: 2, end: 5, probs: [8: 0.8])]
        let issues = [issue("body_sag", .major),
                      issue("low_kick_rate", .minor)]

        // Act
        let model = try XCTUnwrap(IssueTimelineModel.make(
            windows: windows, issues: issues, durationSeconds: 10))

        // Assert
        XCTAssertEqual(model.segments, [
            IssueTimelineModel.Segment(startFraction: 0.0, endFraction: 0.3,
                                       severity: .major, seekTime: 0),
            IssueTimelineModel.Segment(startFraction: 0.3, endFraction: 0.5,
                                       severity: .minor, seekTime: 2)
        ])
        XCTAssertEqual(model.durationSeconds, 10, accuracy: 1e-9)
    }

    // MARK: - Overlap across issues

    func testHigherSeverityWinsWhereIssuesOverlap() throws {
        // Arrange — major body_sag 0–3 overlaps minor low_kick_rate 2–5
        let windows = [window(start: 0, end: 3, probs: [6: 0.9]),
                       window(start: 2, end: 5, probs: [8: 0.8])]
        let issues = [issue("body_sag", .major),
                      issue("low_kick_rate", .minor)]

        // Act
        let model = try XCTUnwrap(IssueTimelineModel.make(
            windows: windows, issues: issues, durationSeconds: 10))

        // Assert — major keeps 0–3; minor only shows its uncovered 3–5 tail
        XCTAssertEqual(model.segments.count, 2)
        let first = try XCTUnwrap(model.segments.first)
        let second = try XCTUnwrap(model.segments.last)
        XCTAssertEqual(first.startFraction, 0.0, accuracy: 1e-9)
        XCTAssertEqual(first.endFraction, 0.3, accuracy: 1e-9)
        XCTAssertEqual(first.severity, .major)
        XCTAssertEqual(first.seekTime, 0, accuracy: 1e-9)
        XCTAssertEqual(second.startFraction, 0.3, accuracy: 1e-9)
        XCTAssertEqual(second.endFraction, 0.5, accuracy: 1e-9)
        XCTAssertEqual(second.severity, .minor)
        XCTAssertEqual(second.seekTime, 2, accuracy: 1e-9)
    }

    func testSegmentsAreSortedAndNonOverlapping() throws {
        // Arrange — three issues with tangled spans
        let windows = [window(start: 0, end: 3, probs: [6: 0.9, 8: 0.8]),
                       window(start: 2, end: 5, probs: [2: 0.7]),
                       window(start: 6, end: 9, probs: [8: 0.9])]
        let issues = [issue("body_sag", .major),
                      issue("left_elbow_collapse", .moderate),
                      issue("low_kick_rate", .minor)]

        // Act
        let model = try XCTUnwrap(IssueTimelineModel.make(
            windows: windows, issues: issues, durationSeconds: 10))

        // Assert
        XCTAssertFalse(model.segments.isEmpty)
        for (a, b) in zip(model.segments, model.segments.dropFirst()) {
            XCTAssertLessThanOrEqual(a.endFraction, b.startFraction + 1e-9)
        }
        model.segments.forEach { XCTAssertGreaterThan($0.widthFraction, 0) }
    }

    // MARK: - Tap → seek mapping

    func testTapInsideSegmentSeeksToRunStart() throws {
        // Arrange — major 0–3 (seek 0), minor tail 3–5 (seek 2) in a 10s clip
        let windows = [window(start: 0, end: 3, probs: [6: 0.9]),
                       window(start: 2, end: 5, probs: [8: 0.8])]
        let model = try XCTUnwrap(IssueTimelineModel.make(
            windows: windows,
            issues: [issue("body_sag", .major), issue("low_kick_rate", .minor)],
            durationSeconds: 10))

        // Act
        let tapInMajor = model.seekTime(atFraction: 0.15)
        let tapInMinor = model.seekTime(atFraction: 0.45)

        // Assert
        XCTAssertEqual(try XCTUnwrap(tapInMajor), 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(tapInMinor), 2, accuracy: 1e-9)
    }

    func testTapOnEmptyTrackReturnsNilAndOutOfRangeClamps() throws {
        // Arrange — single segment covering 0–0.3 of the clip
        let model = try XCTUnwrap(IssueTimelineModel.make(
            windows: [window(start: 0, end: 3, probs: [6: 0.9])],
            issues: [issue("body_sag", .major)],
            durationSeconds: 10))

        // Act & Assert
        XCTAssertNil(model.seekTime(atFraction: 0.9))    // empty track
        XCTAssertNil(model.seekTime(atFraction: .nan))   // junk input
        XCTAssertNil(model.seekTime(atFraction: 1.5))    // clamps to 1 → empty
        XCTAssertEqual(try XCTUnwrap(model.seekTime(atFraction: -0.5)),
                       0, accuracy: 1e-9)                // clamps to 0 → segment
    }

    // MARK: - Hidden states (guards)

    func testHiddenWhenWindowsNilOrEmpty() {
        // Arrange
        let issues = [issue("body_sag", .major)]

        // Act & Assert — legacy sessions (nil) and empty arrays both hide
        XCTAssertNil(IssueTimelineModel.make(windows: nil, issues: issues,
                                             durationSeconds: 10))
        XCTAssertNil(IssueTimelineModel.make(windows: [], issues: issues,
                                             durationSeconds: 10))
    }

    func testHiddenWhenDurationUnknownZeroOrInvalid() {
        // Arrange
        let windows = [window(start: 0, end: 3, probs: [6: 0.9])]
        let issues = [issue("body_sag", .major)]

        // Act & Assert — no division by zero, ever
        XCTAssertNil(IssueTimelineModel.make(windows: windows, issues: issues,
                                             durationSeconds: nil))
        XCTAssertNil(IssueTimelineModel.make(windows: windows, issues: issues,
                                             durationSeconds: 0))
        XCTAssertNil(IssueTimelineModel.make(windows: windows, issues: issues,
                                             durationSeconds: -5))
        XCTAssertNil(IssueTimelineModel.make(windows: windows, issues: issues,
                                             durationSeconds: .nan))
        XCTAssertNil(IssueTimelineModel.make(windows: windows, issues: issues,
                                             durationSeconds: .infinity))
    }

    func testHiddenWhenNoIssuesOrUnknownIssueName() {
        // Arrange
        let windows = [window(start: 0, end: 3, probs: [6: 0.9])]

        // Act & Assert
        XCTAssertNil(IssueTimelineModel.make(windows: windows, issues: [],
                                             durationSeconds: 10))
        XCTAssertNil(IssueTimelineModel.make(windows: windows,
                                             issues: [issue("not_a_label", .major)],
                                             durationSeconds: 10))
    }

    func testHiddenWhenAllWindowsFallOutsideClip() {
        // Arrange — detection opens at 0, so the detected span is 0–10; the
        // only flagged window sits entirely past the end of that span
        let windows = [window(start: 0, end: 3, probs: [6: 0.1]),
                       window(start: 12, end: 15, probs: [6: 0.9])]

        // Act
        let model = IssueTimelineModel.make(windows: windows,
                                            issues: [issue("body_sag", .major)],
                                            durationSeconds: 10)

        // Assert
        XCTAssertNil(model)
    }

    // MARK: - Clamping & fallback

    func testWindowOverhangingClipEndIsClamped() throws {
        // Arrange — detection opens at 0; the last sliding window overruns
        // the clip by rounding
        let windows = [window(start: 0, end: 3, probs: [6: 0.1]),
                       window(start: 8, end: 14, probs: [6: 0.9])]

        // Act
        let model = try XCTUnwrap(IssueTimelineModel.make(
            windows: windows, issues: [issue("body_sag", .major)],
            durationSeconds: 10))

        // Assert — clamped to 0.8–1.0, never past the bar
        XCTAssertEqual(model.segments.count, 1)
        let segment = try XCTUnwrap(model.segments.first)
        XCTAssertEqual(segment.startFraction, 0.8, accuracy: 1e-9)
        XCTAssertEqual(segment.endFraction, 1.0, accuracy: 1e-9)
    }

    func testPeakWindowFallbackWhenNoWindowCrossesThreshold() throws {
        // Arrange — issue flagged from the clip-wide average; every single
        // window sits below threshold, peaking in the middle one
        let windows = [window(start: 0, end: 3, probs: [6: 0.20]),
                       window(start: 3, end: 6, probs: [6: 0.40]),
                       window(start: 6, end: 9, probs: [6: 0.30])]

        // Act
        let model = try XCTUnwrap(IssueTimelineModel.make(
            windows: windows, issues: [issue("body_sag", .major)],
            durationSeconds: 9))

        // Assert — the peak window still marks the strip
        XCTAssertEqual(model.segments.count, 1)
        let segment = try XCTUnwrap(model.segments.first)
        XCTAssertEqual(segment.seekTime, 3, accuracy: 1e-9)
        XCTAssertEqual(segment.startFraction, 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(segment.endFraction, 2.0 / 3.0, accuracy: 1e-9)
    }

    // MARK: - Legend

    func testLegendSeveritiesWorstFirst() throws {
        // Arrange — minor and major present, moderate absent
        let windows = [window(start: 0, end: 3, probs: [6: 0.9]),
                       window(start: 5, end: 8, probs: [8: 0.8])]
        let issues = [issue("low_kick_rate", .minor),
                      issue("body_sag", .major)]

        // Act
        let model = try XCTUnwrap(IssueTimelineModel.make(
            windows: windows, issues: issues, durationSeconds: 10))

        // Assert
        XCTAssertEqual(model.legendSeverities, [.major, .minor])
    }
}
