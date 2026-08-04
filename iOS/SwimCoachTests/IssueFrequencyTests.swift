import XCTest
@testable import SwimCoach

/// Pins the COMMON ISSUES rollup that History's chart renders. The rollup
/// now reads `SwimSession.issueNames` instead of decoding every result
/// blob, so these tests fix the counts, the trend flags, and the top-N cut.
final class IssueFrequencyTests: XCTestCase {

    func testEmptyHistoryProducesNoBars() {
        // Arrange / Act
        let items = IssueFrequency.top(chronological: [])

        // Assert
        XCTAssertTrue(items.isEmpty)
    }

    func testSessionsWithoutFaultsProduceNoBars() {
        // Arrange
        let history: [[String]] = [[], [], []]

        // Act
        let items = IssueFrequency.top(chronological: history)

        // Assert
        XCTAssertTrue(items.isEmpty, "a fault-free history has nothing to chart")
    }

    func testCountsAreSessionsContainingTheFault() {
        // Arrange — body_sag in all 3, low_kick_rate in 1
        let history = [["body_sag"], ["body_sag", "low_kick_rate"], ["body_sag"]]

        // Act
        let items = IssueFrequency.top(chronological: history)

        // Assert
        XCTAssertEqual(items.map(\.name), ["body_sag", "low_kick_rate"])
        XCTAssertEqual(items.map(\.count), [3, 1])
    }

    func testDuplicateNamesInOneSessionCountOnce() {
        // Arrange
        let history = [["body_sag", "body_sag"], ["body_sag"]]

        // Act
        let items = IssueFrequency.top(chronological: history)

        // Assert
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.count, 2, "presence is per session, not per issue")
    }

    func testSortsByDescendingCountAndCapsAtFiveBars() {
        // Arrange — six faults, each appearing in a different number of sessions
        let names = ["a", "b", "c", "d", "e", "f"]
        let history: [[String]] = (0..<6).map { i in Array(names.prefix(6 - i)) }

        // Act
        let items = IssueFrequency.top(chronological: history)

        // Assert
        XCTAssertEqual(items.count, IssueFrequency.maxBars)
        XCTAssertEqual(items.map(\.name), ["a", "b", "c", "d", "e"])
        XCTAssertEqual(items.map(\.count), [6, 5, 4, 3, 2])
    }

    func testFaultFirstSeenMidHistoryIsSessionAligned() {
        // Arrange — 6 sessions; body_sag throughout, stroke_asymmetry only
        // in the recent half, so its leading flags must be false.
        let history = [["body_sag"], ["body_sag"], ["body_sag"],
                       ["body_sag", "stroke_asymmetry"],
                       ["body_sag", "stroke_asymmetry"],
                       ["body_sag", "stroke_asymmetry"]]

        // Act
        let items = IssueFrequency.top(chronological: history)
        let asymmetry = items.first { $0.name == "stroke_asymmetry" }

        // Assert
        XCTAssertEqual(asymmetry?.count, 3)
        XCTAssertEqual(asymmetry?.trend, .worsening,
                       "absent early, present late — leading falses must count")
        XCTAssertEqual(items.first { $0.name == "body_sag" }?.trend, .flat)
    }

    func testFadingFaultReadsAsImproving() {
        // Arrange — low_kick_rate in the older half only (the seeded fixture's shape)
        let history = [["body_sag", "low_kick_rate"], ["body_sag", "low_kick_rate"],
                       ["body_sag", "low_kick_rate"], ["body_sag"],
                       ["body_sag"], ["body_sag"]]

        // Act
        let items = IssueFrequency.top(chronological: history)

        // Assert
        XCTAssertEqual(items.first { $0.name == "low_kick_rate" }?.trend, .improving)
    }

    func testShortHistoryStaysFlat() {
        // Arrange — fewer than IssueTrend.minSessions, so no trend is claimed
        let history = [["body_sag"], [], ["body_sag"]]

        // Act
        let items = IssueFrequency.top(chronological: history)

        // Assert
        XCTAssertEqual(items.first?.trend, .flat)
    }

    /// The pre-change chart keyed presence off `TechniqueIssue.displayName`
    /// from the decoded blob; it now keys off the stored raw name and maps
    /// through the catalog at render time. Both must land on the same label.
    func testRawNamesResolveToTheDisplayLabelsTheBlobCarried() {
        for issue in AnalysisResult.demo.issues {
            XCTAssertEqual(FeedbackEngine.displayInfo(for: issue.name)?.display,
                           issue.displayName)
        }
    }

    /// The seeded training-log fixture: 10 sessions, body_sag and
    /// left_elbow_collapse throughout, low_kick_rate fading out.
    func testSeededFixtureShapeMatchesTheRenderedChart() {
        // Arrange
        let history: [[String]] = (0..<10).map { i in
            i < 5
                ? ["body_sag", "left_elbow_collapse", "low_kick_rate"]
                : ["body_sag", "left_elbow_collapse"]
        }

        // Act
        let items = IssueFrequency.top(chronological: history)

        // Assert
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.first { $0.name == "body_sag" }?.count, 10)
        XCTAssertEqual(items.first { $0.name == "left_elbow_collapse" }?.count, 10)
        XCTAssertEqual(items.first { $0.name == "low_kick_rate" }?.count, 5)
        XCTAssertEqual(items.first { $0.name == "low_kick_rate" }?.trend, .improving)
        XCTAssertEqual(items.prefix(2).map(\.count), [10, 10],
                       "the two ten-session faults sort above the five-session one")
        XCTAssertEqual(items.map(\.name),
                       ["left_elbow_collapse", "body_sag", "low_kick_rate"],
                       "ties break by catalog order, so the chart is reproducible")
    }

    func testEqualCountsBreakByCatalogOrder() {
        // Arrange — three faults in every session, listed out of catalog order
        let history: [[String]] = Array(
            repeating: ["low_kick_rate", "body_sag", "left_elbow_overextension"],
            count: 4)

        // Act
        let items = IssueFrequency.top(chronological: history)

        // Assert — catalog (model probability) order, not insertion or hash order
        XCTAssertEqual(items.map(\.name),
                       ["left_elbow_overextension", "body_sag", "low_kick_rate"])
    }

    func testUnknownFaultNamesSortLastAndStayDeterministic() {
        // Arrange — names outside the catalog have no probability rank
        let history: [[String]] = Array(
            repeating: ["zzz_unknown", "body_sag", "aaa_unknown"], count: 3)

        // Act
        let items = IssueFrequency.top(chronological: history)

        // Assert
        XCTAssertEqual(items.map(\.name), ["body_sag", "aaa_unknown", "zzz_unknown"],
                       "catalog faults first, then unknown names alphabetically")
    }
}
