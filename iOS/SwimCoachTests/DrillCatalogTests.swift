import XCTest
import SwiftData
@testable import SwimCoach

final class DrillCatalogTests: XCTestCase {

    func testEveryDetectableIssueHasAtLeastOneDrill() {
        for issue in FeedbackEngine.issueNames {
            XCTAssertFalse(DrillCatalog.drills(fixing: issue).isEmpty,
                           "no drill fixes \(issue)")
        }
    }

    func testDrillsAreWellFormed() {
        XCTAssertFalse(DrillCatalog.all.isEmpty)
        for drill in DrillCatalog.all {
            XCTAssertFalse(drill.name.isEmpty)
            XCTAssertFalse(drill.goal.isEmpty)
            XCTAssertFalse(drill.dose.isEmpty)
            XCTAssertGreaterThanOrEqual(drill.steps.count, 2, "\(drill.id) has too few steps")
            XCTAssertTrue(drill.steps.allSatisfy { !$0.isEmpty })
        }
    }

    func testDrillIDsAreUnique() {
        let ids = DrillCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testFixesReferenceOnlyRealIssueNames() {
        let valid = Set(FeedbackEngine.issueNames)
        for drill in DrillCatalog.all {
            XCTAssertFalse(drill.fixes.isEmpty, "\(drill.id) fixes nothing")
            for fix in drill.fixes {
                XCTAssertTrue(valid.contains(fix), "\(drill.id) targets unknown issue \(fix)")
            }
        }
    }

    func testPracticeSummaryCountsAndLatestDate() {
        let old = Date(timeIntervalSinceNow: -86400)
        let newer = Date()
        let events = [
            DrillPracticeEvent(drillID: "fist-drill", date: old),
            DrillPracticeEvent(drillID: "fist-drill", date: newer),
            DrillPracticeEvent(drillID: "catch-up", date: old),
        ]
        let summary = DrillPractice.summary(for: "fist-drill", events: events)
        XCTAssertEqual(summary.count, 2)
        XCTAssertEqual(summary.lastDate, newer)
        XCTAssertEqual(DrillPractice.summary(for: "superman-glide", events: events),
                       DrillPractice.Summary(count: 0, lastDate: nil))
    }

    @MainActor
    func testPracticeEventsRoundTripThroughStore() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DrillPracticeEvent.self, configurations: config)
        let context = container.mainContext
        context.insert(DrillPracticeEvent(drillID: "two-beat-timing"))
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<DrillPracticeEvent>())
        XCTAssertEqual(fetched.first?.drillID, "two-beat-timing")
    }

    func testFixingFilterReturnsOnlyMatchingDrills() {
        let drills = DrillCatalog.drills(fixing: "body_sag")
        XCTAssertFalse(drills.isEmpty)
        XCTAssertTrue(drills.allSatisfy { $0.fixes.contains("body_sag") })
    }
}
