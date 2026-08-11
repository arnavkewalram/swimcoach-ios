import XCTest
@testable import SwimCoach

/// The fault page's whole read-out, against the shapes a real library
/// actually produces: a fault that fades out, one that arrives late, one
/// that never lets up, one that was never seen, and no swims at all.
final class FaultHistoryTests: XCTestCase {

    // MARK: - Fixtures

    private let fault = "body_sag"
    private let other = "low_kick_rate"
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// A swim `day` days after `start`, carrying `faults`. `strengths`
    /// defaults to a readable 0.6 for every fault present, which is the
    /// normal case — a stored result that decodes.
    private func swim(_ day: Int,
                      _ faults: [String],
                      strengths: [String: Double]? = nil,
                      swimmer: String = "",
                      score: Int = 60,
                      grade: String = "D") -> FaultHistory.Swim {
        FaultHistory.Swim(
            date: start.addingTimeInterval(Double(day) * 86_400),
            score: score,
            grade: grade,
            swimmer: swimmer,
            faults: faults,
            strengths: strengths ?? Dictionary(uniqueKeysWithValues: faults.map { ($0, 0.6) }))
    }

    private func summary(_ swims: [FaultHistory.Swim],
                         of name: String? = nil,
                         swimmer: String = "") -> FaultHistory.Summary {
        FaultHistory.summary(of: name ?? fault, in: swims, activeSwimmer: swimmer)
    }

    /// Ten swims where the fault is present for the first `presentUntil`
    /// and absent after — the `-seedTrainingLog` shape.
    private func fadingOut(presentUntil: Int) -> [FaultHistory.Swim] {
        (0..<10).map { swim($0, $0 < presentUntil ? [fault, other] : [other]) }
    }

    // MARK: - A fault that fades out

    func testFaultThatFadesOutIsCountedUpToItsLastAppearance() {
        // Arrange — present in swims 1–5 of 10, gone since.
        let swims = fadingOut(presentUntil: 5)

        // Act
        let result = summary(swims)

        // Assert
        XCTAssertEqual(result.totalSwims, 10)
        XCTAssertEqual(result.seenCount, 5)
        XCTAssertEqual(result.firstSeen?.swimIndex, 1)
        XCTAssertEqual(result.lastSeen?.swimIndex, 5)
        XCTAssertEqual(result.swimsSinceLastSeen, 5,
                       "Five swims have been analyzed since it last showed up")
        XCTAssertEqual(result.recentCount, 0,
                       "None of the trailing \(FocusFault.window) swims contained it")
        XCTAssertEqual(result.recentWindow, FocusFault.window)
    }

    func testFaultThatFadesOutReadsAsImproving() {
        XCTAssertEqual(summary(fadingOut(presentUntil: 5)).trend, .improving,
                       "Half a library then nothing is the improving case "
                       + "History's own arrow already shows")
    }

    func testFadedOutFaultSaysHowLongItHasBeenAway() {
        XCTAssertEqual(summary(fadingOut(presentUntil: 5)).standingLine,
                       "Not in your last 5 swims.")
        XCTAssertEqual(summary(fadingOut(presentUntil: 5)).recentLine,
                       "In 0 of your last 5 swims.")
    }

    // MARK: - A fault that appears late

    func testFaultThatAppearsLateStartsAtItsFirstSwim() {
        // Arrange — absent for six swims, present for the last four.
        let swims = (0..<10).map { swim($0, $0 < 6 ? [other] : [fault, other]) }

        // Act
        let result = summary(swims)

        // Assert
        XCTAssertEqual(result.seenCount, 4)
        XCTAssertEqual(result.firstSeen?.swimIndex, 7,
                       "The leading absences must still count toward the library, "
                       + "so 'first seen' is swim 7 of 10 — not swim 1 of 4")
        XCTAssertEqual(result.totalSwims, 10)
        XCTAssertEqual(result.swimsSinceLastSeen, 0)
        XCTAssertEqual(result.standingLine, "Found in your most recent swim.")
        XCTAssertEqual(result.trend, .worsening)
        XCTAssertEqual(result.recentCount, 4)
    }

    func testAppearanceIndicesTrackThePositionInTheLibraryNotTheAppearanceList() {
        // Arrange — every other swim.
        let swims = (0..<6).map { swim($0, $0 % 2 == 0 ? [fault] : []) }

        // Act
        let indices = summary(swims).appearances.map(\.swimIndex)

        // Assert
        XCTAssertEqual(indices, [1, 3, 5],
                       "The chart plots appearances on the library's X axis, so a gap "
                       + "between appearances has to be visible as a gap")
    }

    // MARK: - A fault present throughout

    func testFaultPresentThroughoutIsSeenInEverySwim() {
        // Arrange
        let swims = (0..<8).map { swim($0, [fault]) }

        // Act
        let result = summary(swims)

        // Assert
        XCTAssertEqual(result.seenCount, 8)
        XCTAssertEqual(result.totalSwims, 8)
        XCTAssertEqual(result.trend, .flat, "Never absent is not a direction")
        XCTAssertEqual(result.recentCount, FocusFault.window)
        XCTAssertEqual(result.swimsSinceLastSeen, 0)
        XCTAssertNil(result.empty, "There is plenty to show")
    }

    // MARK: - A fault never seen

    func testFaultNeverSeenReportsTheLibraryItWasNotIn() {
        // Arrange
        let swims = (0..<7).map { swim($0, [other]) }

        // Act
        let result = summary(swims)

        // Assert
        XCTAssertFalse(result.isSeen)
        XCTAssertEqual(result.totalSwims, 7)
        XCTAssertTrue(result.appearances.isEmpty)
        XCTAssertNil(result.firstSeen)
        XCTAssertNil(result.swimsSinceLastSeen,
                     "'Not in your last N swims' is meaningless when there was never a last")
        XCTAssertNil(result.standingLine)
        XCTAssertEqual(result.empty?.headline, "Not seen in your swims")
        XCTAssertEqual(result.empty?.detail,
                       "The model hasn't flagged this in any of your 7 swims.")
    }

    // MARK: - Empty history

    func testEmptyHistoryClaimsNothingAboutTheSwimmer() {
        // Act
        let result = summary([])

        // Assert
        XCTAssertEqual(result.totalSwims, 0)
        XCTAssertEqual(result.recentCount, 0)
        XCTAssertEqual(result.recentWindow, 0, "There is no window to look back over")
        XCTAssertEqual(result.trend, .flat)
        XCTAssertNil(result.strength)
        XCTAssertNil(result.swimsSinceLastSeen)
        XCTAssertEqual(result.empty?.headline, "No swims analyzed yet",
                       "An empty library must not read as 'never seen', which is a "
                       + "claim about swims that were never analyzed")
    }

    // MARK: - Detection strength

    func testStrengthShiftNeedsEnoughReadings() {
        // Arrange — one short of the gate, and a huge drop.
        let short = (0..<(FaultHistory.minStrengthSamples - 1)).map {
            swim($0, [fault], strengths: [fault: $0 == 0 ? 0.95 : 0.10])
        }

        // Assert
        XCTAssertNil(summary(short).strength,
                     "Below \(FaultHistory.minStrengthSamples) readings there is no "
                     + "half to compare against")
    }

    func testFallingConfidenceReadsAsEasing() {
        // Arrange — 0.90, 0.88 then 0.50, 0.48.
        let strengths = [0.90, 0.88, 0.50, 0.48]
        let swims = strengths.enumerated().map { swim($0.offset, [fault],
                                                      strengths: [fault: $0.element]) }

        // Act
        let shift = summary(swims).strength

        // Assert
        XCTAssertEqual(shift?.move, .easing)
        XCTAssertEqual(shift?.earlierMean ?? 0, 0.89, accuracy: 0.0001)
        XCTAssertEqual(shift?.recentMean ?? 0, 0.49, accuracy: 0.0001)
        XCTAssertEqual(shift?.detail, "Averaged 89% early, 49% lately.")
    }

    func testRisingConfidenceReadsAsBuilding() {
        let swims = [0.50, 0.52, 0.90, 0.88].enumerated().map {
            swim($0.offset, [fault], strengths: [fault: $0.element])
        }
        XCTAssertEqual(summary(swims).strength?.move, .building)
    }

    /// The gate is the point: a move under the threshold is model noise.
    func testMoveUnderTheThresholdIsSteady() {
        let nudge = FaultHistory.strengthThreshold / 2
        let swims = [0.60, 0.60, 0.60 + nudge, 0.60 + nudge].enumerated().map {
            swim($0.offset, [fault], strengths: [fault: $0.element])
        }
        XCTAssertEqual(summary(swims).strength?.move, .steady)
    }

    /// A swim whose stored result would not decode still contained the
    /// fault — its `issueNames` column says so. Counting it as fault-free
    /// would manufacture an improvement, so it counts and plots nothing.
    func testUnreadableSwimStillCountsButPlotsNoPoint() {
        // Arrange — swim 2 of 3 has no strength for the fault.
        let swims = [swim(0, [fault], strengths: [fault: 0.8]),
                     swim(1, [fault], strengths: [:]),
                     swim(2, [fault], strengths: [fault: 0.7])]

        // Act
        let result = summary(swims)

        // Assert
        XCTAssertEqual(result.seenCount, 3, "Frequency counts every appearance")
        XCTAssertEqual(result.plottable.count, 2, "Only the readable ones plot")
        XCTAssertEqual(result.plottable.map(\.run), [0, 1],
                       "The line must break across the reading it could not take, "
                       + "not draw straight through it")
    }

    func testConsecutiveReadableAppearancesShareOneRun() {
        let swims = (0..<4).map { swim($0, [fault], strengths: [fault: 0.6]) }
        XCTAssertEqual(summary(swims).plottable.map(\.run), [0, 0, 0, 0])
    }

    // MARK: - Swimmer scope

    /// The boundary and every statistic go through `DrillEffect`'s one rule,
    /// applied inside `summary` — a caller cannot scope one and not another.
    func testNamedSwimmerSeesOnlyTheirOwnSwims() {
        // Arrange — Maya has the fault twice, Arnav never.
        let swims = [swim(0, [fault], swimmer: "Maya"),
                     swim(1, [other], swimmer: "Arnav"),
                     swim(2, [other], swimmer: "Arnav"),
                     swim(3, [fault], swimmer: "Maya")]

        // Act
        let maya = summary(swims, swimmer: "Maya")
        let arnav = summary(swims, swimmer: "Arnav")

        // Assert
        XCTAssertEqual(maya.totalSwims, 2)
        XCTAssertEqual(maya.seenCount, 2)
        XCTAssertEqual(maya.firstSeen?.swimIndex, 1,
                       "Indices are positions in the SCOPED library, so Maya's first "
                       + "swim is swim 1 — not swim 1 of everyone's")
        XCTAssertEqual(arnav.totalSwims, 2)
        XCTAssertFalse(arnav.isSeen)
    }

    func testEmptyScopeIsEveryone() {
        let swims = [swim(0, [fault], swimmer: "Maya"),
                     swim(1, [fault], swimmer: "Arnav")]
        XCTAssertEqual(summary(swims).totalSwims, 2)
        XCTAssertEqual(summary(swims).seenCount, 2)
    }

    /// Same stale-name guard `DrillEffect` and Home already apply: a
    /// swimmer the library no longer knows falls back to everyone rather
    /// than blanking the page.
    func testUnknownSwimmerFallsBackToEveryone() {
        let swims = [swim(0, [fault], swimmer: "Maya"),
                     swim(1, [fault], swimmer: "Arnav")]
        XCTAssertEqual(summary(swims, swimmer: "Deleted").totalSwims, 2)
    }

    // MARK: - What costs a disk read

    /// The page's performance contract. `observedValue` lives only inside
    /// the externally-stored result blob, and this app has shipped a fix
    /// twice (v1.43.4, v1.45.5) for reading one more often than it had to.
    func testOnlySwimsCarryingTheFaultCostAResultDecode() {
        // Arrange — a hundred swims, three of which had this fault.
        let carriers = Set([7, 42, 91])
        let library = (0..<100).map { i in
            (names: carriers.contains(i) ? [self.fault, self.other] : [self.other],
             count: carriers.contains(i) ? 2 : 1)
        }

        // Act
        let opens = library.filter {
            FaultHistory.needsResultBlob(issueNames: $0.names,
                                         issueCount: $0.count,
                                         fault: fault)
        }.count

        // Assert
        XCTAssertEqual(opens, carriers.count,
                       "97 swims that never had this fault must be answered from "
                       + "columns alone — opening their blobs is the cost this "
                       + "page exists to avoid paying")
    }

    func testACleanLibraryCostsNoDecodesAtAll() {
        let clean = (0..<50).map { _ in ([self.other], 1) }
        XCTAssertEqual(clean.filter {
            FaultHistory.needsResultBlob(issueNames: $0.0, issueCount: $0.1, fault: fault)
        }.count, 0)
    }

    /// A row saved before `issueNames` existed has no other record of what
    /// it contained, so it is the one case that must open regardless.
    func testLegacyRowsStillHaveToBeOpened() {
        XCTAssertTrue(FaultHistory.needsResultBlob(issueNames: [], issueCount: 3,
                                                   fault: fault))
        XCTAssertFalse(FaultHistory.needsResultBlob(issueNames: [], issueCount: 0,
                                                    fault: fault),
                       "A swim with no faults at all is not a legacy row")
    }

    // MARK: - Ordering

    func testSwimsAreOrderedChronologicallyRegardlessOfInputOrder() {
        // Arrange — newest first, the order `@Query` hands History.
        let swims = [swim(9, [fault], strengths: [fault: 0.3]),
                     swim(4, [fault], strengths: [fault: 0.6]),
                     swim(0, [fault], strengths: [fault: 0.9])]

        // Act
        let result = summary(swims)

        // Assert
        XCTAssertEqual(result.appearances.map(\.strength), [0.9, 0.6, 0.3])
        XCTAssertEqual(result.firstSeen?.date, start)
    }
}
