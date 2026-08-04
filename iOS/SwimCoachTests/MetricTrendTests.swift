import XCTest
@testable import SwimCoach

final class MetricTrendTests: XCTestCase {

    /// Entry at a deterministic day offset. Defaults are fully plottable:
    /// 30 strokes over 60 s = 30 strokes/min, 90 kicks/min.
    private func entry(day: Int,
                       strokes: Int = 30,
                       duration: Double = 60,
                       kickRate: Double = 90) -> MetricTrend.Entry {
        MetricTrend.Entry(
            date: Date(timeIntervalSinceReferenceDate: Double(day) * 86_400),
            strokeCount: strokes,
            durationSeconds: duration,
            kickRatePerMin: kickRate)
    }

    // MARK: Derivation

    func testStrokeRateDerivedFromStoredCountAndDuration() {
        // Arrange: 45 strokes over 90 seconds
        let entries = [entry(day: 0, strokes: 45, duration: 90), entry(day: 1)]

        // Act
        let trend = MetricTrend.build(entries: entries)

        // Assert: 45 strokes / 1.5 min = 30 strokes/min
        XCTAssertEqual(trend.strokeRate.points[0].value, 30, accuracy: 0.001)
        XCTAssertEqual(trend.kickRate.points[0].value, 90, accuracy: 0.001)
    }

    // MARK: Gapping

    func testZeroDurationGapsStrokeRateButKeepsKickRate() {
        // Arrange: middle session predates stored durations (0 = unknown)
        let entries = [entry(day: 0), entry(day: 1, duration: 0), entry(day: 2)]

        // Act
        let trend = MetricTrend.build(entries: entries)

        // Assert: no point at index 2, and no zero value ever plotted
        XCTAssertEqual(trend.strokeRate.points.map(\.index), [1, 3])
        XCTAssertFalse(trend.strokeRate.points.contains { $0.value == 0 })
        XCTAssertEqual(trend.kickRate.points.map(\.index), [1, 2, 3])
    }

    func testZeroKickRateIsGapped() {
        // Arrange
        let entries = [entry(day: 0), entry(day: 1, kickRate: 0), entry(day: 2)]

        // Act
        let trend = MetricTrend.build(entries: entries)

        // Assert
        XCTAssertEqual(trend.kickRate.points.map(\.index), [1, 3])
        XCTAssertEqual(trend.strokeRate.points.map(\.index), [1, 2, 3])
    }

    func testGapSplitsLineIntoSeparateRuns() {
        // Arrange: sessions 1-2 plottable, 3 gapped, 4-5 plottable
        let entries = [
            entry(day: 0), entry(day: 1),
            entry(day: 2, strokes: 0),
            entry(day: 3), entry(day: 4),
        ]

        // Act
        let trend = MetricTrend.build(entries: entries)

        // Assert: the line breaks at the gap instead of drawing across it
        XCTAssertEqual(trend.strokeRate.points.map(\.run), [0, 0, 1, 1])
        XCTAssertEqual(trend.kickRate.points.map(\.run), [0, 0, 0, 0, 0])
    }

    // MARK: Ordering

    func testEntriesAreSortedChronologicallyBeforeIndexing() {
        // Arrange: newest first, as @Query hands sessions to HistoryView
        let entries = [
            entry(day: 2, kickRate: 100),
            entry(day: 1, kickRate: 95),
            entry(day: 0, kickRate: 90),
        ]

        // Act
        let trend = MetricTrend.build(entries: entries)

        // Assert: index 1 = oldest, latest = newest session's value
        XCTAssertEqual(trend.kickRate.points.map(\.value), [90, 95, 100])
        XCTAssertEqual(trend.kickRate.latest, 100)
    }

    // MARK: Needs-two gate

    func testSinglePlottableSessionIsNotPlottable() {
        // Arrange: one full session + one with no metrics at all
        let entries = [entry(day: 0),
                       entry(day: 1, strokes: 0, duration: 0, kickRate: 0)]

        // Act
        let trend = MetricTrend.build(entries: entries)

        // Assert
        XCTAssertFalse(trend.isPlottable)
    }

    func testTwoPlottableSessionsInOneSeriesIsPlottable() {
        // Arrange: stroke rate never derivable, kick rate twice
        let entries = [entry(day: 0, duration: 0), entry(day: 1, duration: 0)]

        // Act
        let trend = MetricTrend.build(entries: entries)

        // Assert
        XCTAssertTrue(trend.isPlottable)
        XCTAssertTrue(trend.strokeRate.points.isEmpty)
    }

    // MARK: Caption

    func testCaptionReportsLatestValueOfEachSeries() {
        // Arrange
        let entries = [entry(day: 0),
                       entry(day: 1, strokes: 34, duration: 60, kickRate: 101.6)]

        // Act
        let trend = MetricTrend.build(entries: entries)

        // Assert
        XCTAssertEqual(trend.caption, "Latest: 34 strokes/min · 102 kicks/min")
    }

    func testCaptionOmitsSeriesWithNoDataAndNilsOutWhenEmpty() {
        // Arrange
        let kickOnly = MetricTrend.build(entries: [
            entry(day: 0, duration: 0, kickRate: 88.4),
            entry(day: 1, duration: 0, kickRate: 90.2),
        ])
        let empty = MetricTrend.build(entries: [])

        // Act & Assert
        XCTAssertEqual(kickOnly.caption, "Latest: 90 kicks/min")
        XCTAssertNil(empty.caption)
    }
}
