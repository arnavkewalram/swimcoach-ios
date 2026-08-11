import XCTest
@testable import SwimCoach

/// The distinction v1.47.3 drew on Drills, held on the fault page: a
/// measured finding and a refusal to give one must not be the same shape.
///
/// These tests exist because the two used to be one dim branch of the other
/// — ABOUT THE SAME and NOT ENOUGH SWIMS YET rendered byte-identically on the
/// drill card, and the first draft of this page reproduced it in two new
/// places (a fault with under `IssueTrend.minSessions` swims silently lost
/// its chip; a chart with two readings drew a line and said nothing about
/// whether it meant anything). A shape that is only guaranteed by whichever
/// branch of a `body` happened to run is not guaranteed.
final class FaultDetailPresentationTests: XCTestCase {

    private let fault = "body_sag"
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func swim(_ day: Int, _ faults: [String],
                      strengths: [String: Double]? = nil) -> FaultHistory.Swim {
        FaultHistory.Swim(
            date: start.addingTimeInterval(Double(day) * 86_400),
            grade: "D",
            faults: faults,
            strengths: strengths ?? Dictionary(uniqueKeysWithValues: faults.map { ($0, 0.6) }))
    }

    private func summary(_ swims: [FaultHistory.Swim]) -> FaultHistory.Summary {
        FaultHistory.summary(of: fault, in: swims)
    }

    /// Readings of the fault, one per swim, so a strength case is one line.
    private func readings(_ values: [Double]) -> FaultHistory.Summary {
        summary(values.enumerated().map {
            swim($0.offset, [fault], strengths: [fault: $0.element])
        })
    }

    // MARK: - Recurrence: measured vs refused

    func testShortLibraryRefusesInsteadOfShowingALevelVerdict() {
        // Arrange — under IssueTrend.minSessions, so nothing is measurable.
        let short = summary((0..<3).map { swim($0, [fault]) })

        // Act
        let readout = FaultDetailPresentation.recurrence(short)

        // Assert
        XCTAssertFalse(readout.isMeasured,
                       "Under \(IssueTrend.minSessions) swims the app has not measured "
                       + "a direction, so it must not wear the chip that says it has")
        guard case .note(let headline, let detail) = readout else {
            return XCTFail("Expected the quiet register, got \(readout)")
        }
        XCTAssertEqual(headline, "Too little history to call it")
        XCTAssertTrue(detail.contains("3 swims on record"), detail)
        XCTAssertTrue(detail.contains("\(IssueTrend.minSessions) needed"), detail)
    }

    func testALevelTrendOverEnoughSwimsIsAMeasuredVerdict() {
        // Arrange — present throughout, which IssueTrend calls flat.
        let steady = summary((0..<IssueTrend.minSessions).map { swim($0, [fault]) })

        // Act
        let readout = FaultDetailPresentation.recurrence(steady)

        // Assert — "we looked and it did not move" IS a finding, and it says
        // so in the same words the drill card uses for the same result.
        XCTAssertTrue(readout.isMeasured)
        guard case .verdict(let label, let arrow, let tone, _) = readout else {
            return XCTFail("Expected a verdict, got \(readout)")
        }
        XCTAssertEqual(label, "ABOUT THE SAME")
        XCTAssertNil(arrow, "Nothing moved, so no direction mark")
        XCTAssertEqual(tone, .flat)
    }

    /// The whole point: the two cases above must not render alike.
    func testALevelVerdictAndAShortLibraryAreDifferentShapes() {
        let measured = FaultDetailPresentation.recurrence(
            summary((0..<IssueTrend.minSessions).map { swim($0, [fault]) }))
        let refused = FaultDetailPresentation.recurrence(
            summary((0..<(IssueTrend.minSessions - 1)).map { swim($0, [fault]) }))

        XCTAssertNotEqual(measured, refused)
        XCTAssertTrue(measured.isMeasured)
        XCTAssertFalse(refused.isMeasured)
    }

    func testFadingFaultReadsAsShowingUpLess() {
        let fading = summary((0..<10).map { swim($0, $0 < 5 ? [fault] : []) })
        guard case .verdict(let label, let arrow, let tone, _) =
                FaultDetailPresentation.recurrence(fading) else {
            return XCTFail("Expected a verdict")
        }
        XCTAssertEqual(label, "SHOWING UP LESS")
        XCTAssertEqual(arrow, "arrow.down.right")
        XCTAssertEqual(tone, .receding, "A fault receding is the same green here, "
                       + "on the drill card and on History's arrow")
    }

    func testArrivingFaultReadsAsShowingUpMore() {
        let arriving = summary((0..<10).map { swim($0, $0 < 6 ? [] : [fault]) })
        guard case .verdict(let label, let arrow, let tone, _) =
                FaultDetailPresentation.recurrence(arriving) else {
            return XCTFail("Expected a verdict")
        }
        XCTAssertEqual(label, "SHOWING UP MORE")
        XCTAssertEqual(arrow, "arrow.up.right")
        XCTAssertEqual(tone, .advancing)
    }

    // MARK: - Strength: measured vs refused

    func testTooFewReadingsRefuseRatherThanReadAsSteady() {
        // Arrange — three readings with a huge fall in them. STEADY here
        // would be a claim about a sample the gate has not cleared.
        let readout = FaultDetailPresentation.strength(readings([0.95, 0.90, 0.20]))

        // Assert
        XCTAssertFalse(readout.isMeasured)
        guard case .note(let headline, let detail) = readout else {
            return XCTFail("Expected the quiet register, got \(readout)")
        }
        XCTAssertEqual(headline, "Not enough readings yet")
        XCTAssertTrue(detail.contains("3 readings"), detail)
        XCTAssertTrue(detail.contains("\(FaultHistory.minStrengthSamples) needed"), detail)
    }

    func testOneReadingSaysWhatALineNeeds() {
        guard case .note(let headline, let detail) =
                FaultDetailPresentation.strength(readings([0.7])) else {
            return XCTFail("Expected the quiet register")
        }
        XCTAssertEqual(headline, "One reading so far")
        XCTAssertTrue(detail.contains("two readings"), detail)
    }

    /// Seen, but every one of those swims' blobs is unreadable — the page
    /// has a frequency and no series, and has to say why the chart is gone.
    func testNoReadableReadingsExplainsTheEmptyChart() {
        let unreadable = summary((0..<6).map { swim($0, [fault], strengths: [:]) })
        XCTAssertTrue(unreadable.isSeen, "The appearances still count")
        guard case .note(let headline, let detail) =
                FaultDetailPresentation.strength(unreadable) else {
            return XCTFail("Expected the quiet register")
        }
        XCTAssertEqual(headline, "No readings on record")
        XCTAssertTrue(detail.contains("nothing to plot"), detail)
    }

    func testEnoughReadingsEarnAChip() {
        let readout = FaultDetailPresentation.strength(readings([0.90, 0.88, 0.50, 0.48]))

        XCTAssertTrue(readout.isMeasured)
        guard case .verdict(let label, let arrow, let tone, let detail) = readout else {
            return XCTFail("Expected a verdict, got \(readout)")
        }
        XCTAssertEqual(label, "EASING")
        XCTAssertEqual(arrow, "arrow.down.right")
        XCTAssertEqual(tone, .receding)
        XCTAssertEqual(detail, "Averaged 89% early, 49% lately.",
                       "A chip has to carry the numbers it came from")
    }

    /// STEADY is a measurement — "we compared the halves and they matched" —
    /// so unlike the three-reading case above it keeps its chip.
    func testASteadySeriesOverTheGateIsStillMeasured() {
        let readout = FaultDetailPresentation.strength(readings([0.60, 0.61, 0.60, 0.62]))
        XCTAssertTrue(readout.isMeasured)
        guard case .verdict(let label, let arrow, _, _) = readout else {
            return XCTFail("Expected a verdict")
        }
        XCTAssertEqual(label, "STEADY")
        XCTAssertNil(arrow)
    }

    func testSteadyAndTooFewReadingsAreDifferentShapes() {
        let measured = FaultDetailPresentation.strength(readings([0.60, 0.61, 0.60, 0.62]))
        let refused = FaultDetailPresentation.strength(readings([0.60, 0.61, 0.60]))
        XCTAssertNotEqual(measured, refused)
        XCTAssertTrue(measured.isMeasured)
        XCTAssertFalse(refused.isMeasured)
    }

    // MARK: - A row that cannot be opened

    /// The fault page routes a tapped appearance to its Results by decoding
    /// the same blob the confidence came from. When that blob will not
    /// decode there is no confidence AND no destination — one fact, so the
    /// row must not be offered as a way through.
    func testAnAppearanceWithNoReadingIsNotOpenable() {
        let mixed = summary([swim(0, [fault], strengths: [fault: 0.8]),
                             swim(1, [fault], strengths: [:])])
        XCTAssertEqual(mixed.appearances.map(\.resultIsReadable), [true, false])
        XCTAssertEqual(mixed.appearances.map { $0.strength != nil },
                       mixed.appearances.map(\.resultIsReadable),
                       "`resultIsReadable` names the fact `strength == nil` already "
                       + "carries — if these ever disagree the page has two truths")
    }
}
