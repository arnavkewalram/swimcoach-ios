import XCTest
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

    func testFixingFilterReturnsOnlyMatchingDrills() {
        let drills = DrillCatalog.drills(fixing: "body_sag")
        XCTAssertFalse(drills.isEmpty)
        XCTAssertTrue(drills.allSatisfy { $0.fixes.contains("body_sag") })
    }
}
