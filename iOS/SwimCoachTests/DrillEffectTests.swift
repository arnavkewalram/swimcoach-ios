import XCTest
@testable import SwimCoach

final class DrillEffectTests: XCTestCase {

    // MARK: - Fixtures

    private let fixes = ["low_kick_rate"]
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// A swim `days` before (negative) or after (positive) `start`.
    private func swim(_ days: Double,
                      _ names: [String],
                      swimmer: String = "") -> DrillEffect.Swim {
        DrillEffect.Swim(date: start.addingTimeInterval(days * 86_400),
                         issueNames: names,
                         swimmer: swimmer)
    }

    private func readout(fixes: [String]? = nil,
                         practices: [Date]? = nil,
                         swims: [DrillEffect.Swim],
                         swimmer: String = "") -> DrillEffect.Result {
        DrillEffect.result(fixes: fixes ?? self.fixes,
                           practiceDates: practices ?? [start],
                           swims: swims,
                           activeSwimmer: swimmer)
    }

    private func hit(_ days: Double) -> DrillEffect.Swim { swim(days, ["low_kick_rate"]) }
    private func clean(_ days: Double) -> DrillEffect.Swim { swim(days, ["body_sag"]) }

    // MARK: - Verdicts

    func testFaultAppearingLessSinceFirstPracticeIsLessOften() {
        // 3 of 3 before → 0 of 3 since: a 100-point drop.
        let result = readout(swims: [hit(-9), hit(-6), hit(-3),
                                     clean(1), clean(4), clean(7)])
        guard case .measured(let r) = result else { return XCTFail("expected a verdict, got \(result)") }
        XCTAssertEqual(r.verdict, .lessOften)
        XCTAssertEqual(r.beforeHits, 3)
        XCTAssertEqual(r.beforeTotal, 3)
        XCTAssertEqual(r.afterHits, 0)
        XCTAssertEqual(r.afterTotal, 3)
    }

    func testFaultAppearingMoreSinceFirstPracticeIsMoreOften() {
        let result = readout(swims: [clean(-9), clean(-6), clean(-3),
                                     hit(1), hit(4), hit(7)])
        guard case .measured(let r) = result else { return XCTFail("expected a verdict, got \(result)") }
        XCTAssertEqual(r.verdict, .moreOften)
        XCTAssertEqual(r.beforeHits, 0)
        XCTAssertEqual(r.afterHits, 3)
    }

    func testPersistentFaultIsUnchanged() {
        let result = readout(swims: [hit(-9), hit(-6), hit(-3),
                                     hit(1), hit(4), hit(7)])
        guard case .measured(let r) = result else { return XCTFail("expected a verdict, got \(result)") }
        XCTAssertEqual(r.verdict, .unchanged)
        XCTAssertEqual(r.beforeHits, 3)
        XCTAssertEqual(r.afterHits, 3)
    }

    func testAnyTargetedFaultCountsAsAHit() {
        // The drill targets a cluster; either member showing up is a hit.
        let result = readout(
            fixes: ["left_elbow_collapse", "right_elbow_collapse"],
            swims: [swim(-9, ["left_elbow_collapse"]),
                    swim(-6, ["right_elbow_collapse"]),
                    swim(-3, ["left_elbow_collapse", "body_sag"]),
                    clean(1), clean(4), clean(7)])
        guard case .measured(let r) = result else { return XCTFail("expected a verdict, got \(result)") }
        XCTAssertEqual(r.beforeHits, 3)
        XCTAssertEqual(r.verdict, .lessOften)
    }

    // MARK: - Minimum-sample boundary

    func testExactlyThreeSwimsEachSideIsEnough() {
        let result = readout(swims: [hit(-3), hit(-2), hit(-1),
                                     clean(1), clean(2), clean(3)])
        guard case .measured = result else { return XCTFail("3 a side must be measurable, got \(result)") }
    }

    func testOneSwimOfMovementAtTheMinimumSampleStaysUnchanged() {
        // 3/3 → 2/3 is a 33-point move: one swim, below the 34-point bar.
        // This is the whole point of the gate — a single bad day cannot
        // produce a verdict.
        let result = readout(swims: [hit(-3), hit(-2), hit(-1),
                                     hit(1), hit(2), clean(3)])
        guard case .measured(let r) = result else { return XCTFail("expected a verdict, got \(result)") }
        XCTAssertEqual(r.verdict, .unchanged)
    }

    func testTwoSwimsOfMovementAtTheMinimumSampleIsAVerdict() {
        // 3/3 → 1/3 is a 67-point move: two swims, clears the bar.
        let result = readout(swims: [hit(-3), hit(-2), hit(-1),
                                     hit(1), clean(2), clean(3)])
        guard case .measured(let r) = result else { return XCTFail("expected a verdict, got \(result)") }
        XCTAssertEqual(r.verdict, .lessOften)
    }

    // MARK: - Insufficient data

    func testNoPracticesIsNeverPractised() {
        let result = readout(practices: [],
                             swims: [hit(-3), hit(-2), hit(-1),
                                     clean(1), clean(2), clean(3)])
        XCTAssertEqual(result, .notEnough(.neverPractised))
    }

    func testPractisedButNoSwimsSinceIsTooFewAfter() {
        let result = readout(swims: [hit(-3), hit(-2), hit(-1)])
        XCTAssertEqual(result, .notEnough(.tooFewAfter(have: 0)))
    }

    func testSomeButNotEnoughSwimsSinceIsTooFewAfter() {
        let result = readout(swims: [hit(-3), hit(-2), hit(-1), clean(1), clean(2)])
        XCTAssertEqual(result, .notEnough(.tooFewAfter(have: 2)))
    }

    func testTooFewSwimsBeforeTheFirstPractice() {
        let result = readout(swims: [hit(-1), clean(1), clean(2), clean(3), clean(4)])
        XCTAssertEqual(result, .notEnough(.tooFewBefore(have: 1)))
    }

    func testShortOnBothSidesReportsTheBaselineSideFirst() {
        // Only the baseline is unfixable, so it is the honest answer.
        let result = readout(swims: [hit(-1), clean(1)])
        XCTAssertEqual(result, .notEnough(.tooFewBefore(have: 1)))
    }

    func testFaultThatNeverAppearsIsNotTracked() {
        let result = readout(swims: [clean(-3), clean(-2), clean(-1),
                                     clean(1), clean(2), clean(3)])
        XCTAssertEqual(result, .notEnough(.faultNotSeen))
    }

    func testNoSwimsAtAllIsNotReportedAsAnAbsentFault() {
        // "Hasn't shown up" would be a claim about swims that don't exist.
        XCTAssertEqual(readout(swims: []), .notEnough(.tooFewBefore(have: 0)))
    }

    func testFaultNotSeenOutranksAShortBaseline() {
        let result = readout(swims: [clean(-1), clean(1), clean(2), clean(3), clean(4)])
        XCTAssertEqual(result, .notEnough(.faultNotSeen))
    }

    // MARK: - Boundary and ordering

    func testEarliestPracticeSetsTheBoundaryRegardlessOfInputOrder() {
        let taps = [start.addingTimeInterval(20 * 86_400),
                    start,
                    start.addingTimeInterval(9 * 86_400)]
        // Swims shuffled too — the split must not depend on arrival order.
        let swims = [clean(4), hit(-6), clean(7), hit(-9), clean(1), hit(-3)]
        let result = readout(practices: taps, swims: swims)
        guard case .measured(let r) = result else { return XCTFail("expected a verdict, got \(result)") }
        XCTAssertEqual(r.beforeTotal, 3, "everything before the FIRST tap is baseline")
        XCTAssertEqual(r.afterTotal, 3)
        XCTAssertEqual(r.verdict, .lessOften)
    }

    func testSwimOnTheBoundaryInstantCountsAsAfter() {
        let onTap = DrillEffect.Swim(date: start, issueNames: ["low_kick_rate"])
        let result = readout(swims: [hit(-3), hit(-2), hit(-1),
                                     onTap, clean(2), clean(3)])
        guard case .measured(let r) = result else { return XCTFail("expected a verdict, got \(result)") }
        XCTAssertEqual(r.beforeTotal, 3)
        XCTAssertEqual(r.afterTotal, 3)
        XCTAssertEqual(r.afterHits, 1)
    }

    // MARK: - Swimmer scope

    func testOnlyTheActiveSwimmersSwimsCount() {
        let swims = [
            swim(-3, ["low_kick_rate"], swimmer: "Arnav"),
            swim(-2, ["low_kick_rate"], swimmer: "Arnav"),
            swim(-1, ["low_kick_rate"], swimmer: "Arnav"),
            swim(1, ["body_sag"], swimmer: "Arnav"),
            swim(2, ["body_sag"], swimmer: "Arnav"),
            swim(3, ["body_sag"], swimmer: "Arnav"),
            // Maya's swims would flip the verdict if they leaked in.
            swim(-3, ["body_sag"], swimmer: "Maya"),
            swim(-2, ["body_sag"], swimmer: "Maya"),
            swim(-1, ["body_sag"], swimmer: "Maya"),
            swim(1, ["low_kick_rate"], swimmer: "Maya"),
            swim(2, ["low_kick_rate"], swimmer: "Maya"),
            swim(3, ["low_kick_rate"], swimmer: "Maya"),
        ]
        guard case .measured(let arnav) = readout(swims: swims, swimmer: "Arnav")
        else { return XCTFail("expected a verdict for Arnav") }
        XCTAssertEqual(arnav.verdict, .lessOften)
        XCTAssertEqual(arnav.beforeTotal, 3)
        XCTAssertEqual(arnav.afterTotal, 3)

        guard case .measured(let maya) = readout(swims: swims, swimmer: "Maya")
        else { return XCTFail("expected a verdict for Maya") }
        XCTAssertEqual(maya.verdict, .moreOften)

        // Unscoped, the two cancel to no movement.
        guard case .measured(let everyone) = readout(swims: swims)
        else { return XCTFail("expected a verdict for everyone") }
        XCTAssertEqual(everyone.verdict, .unchanged)
        XCTAssertEqual(everyone.beforeTotal, 6)
    }

    func testUnknownSwimmerFallsBackToEveryone() {
        // Matches HomeView: a stale name must not blank every card.
        let swims = [swim(-3, ["low_kick_rate"], swimmer: "Arnav"),
                     swim(-2, ["low_kick_rate"], swimmer: "Arnav"),
                     swim(-1, ["low_kick_rate"], swimmer: "Arnav"),
                     swim(1, ["body_sag"], swimmer: "Arnav"),
                     swim(2, ["body_sag"], swimmer: "Arnav"),
                     swim(3, ["body_sag"], swimmer: "Arnav")]
        XCTAssertEqual(DrillEffect.scoped(swims, to: "Deleted").count, 6)
        guard case .measured = readout(swims: swims, swimmer: "Deleted")
        else { return XCTFail("expected the fallback to still produce a verdict") }
    }

    // MARK: - Legacy rows

    func testLegacyRowDetection() {
        // Saved before `issueNames` existed: empty column, non-zero count.
        XCTAssertTrue(DrillEffect.isLegacyRow(issueNames: [], issueCount: 3))
        // A genuinely clean modern swim.
        XCTAssertFalse(DrillEffect.isLegacyRow(issueNames: [], issueCount: 0))
        // Modern rows with faults.
        XCTAssertFalse(DrillEffect.isLegacyRow(issueNames: ["body_sag"], issueCount: 1))
    }

    // MARK: - Copy

    func testCopyNeverClaimsTheDrillCausedTheChange() {
        let verdicts: [DrillEffect.Verdict] = [.lessOften, .moreOften, .unchanged]
        let banned = ["fixed", "caused", "because", "thanks to", "worked"]
        for verdict in verdicts {
            let r = DrillEffect.Readout(verdict: verdict, beforeHits: 3, beforeTotal: 4,
                                        afterHits: 1, afterTotal: 5)
            let text = ([r.headline, r.detail, r.caveat ?? ""]).joined(separator: " ").lowercased()
            for word in banned {
                XCTAssertFalse(text.contains(word), "\(verdict) copy claims causation: \(text)")
            }
            XCTAssertTrue(r.detail.contains("before you started"))
        }
    }

    func testMovementVerdictsCarryTheCorrelationCaveat() {
        func caveat(_ v: DrillEffect.Verdict) -> String? {
            DrillEffect.Readout(verdict: v, beforeHits: 4, beforeTotal: 5,
                                afterHits: 0, afterTotal: 5).caveat
        }
        XCTAssertNotNil(caveat(.lessOften))
        XCTAssertNotNil(caveat(.moreOften))
        XCTAssertNil(caveat(.unchanged), "no claim to misread when nothing moved")
    }

    func testReadoutDetailShowsTheRawFractions() {
        let r = DrillEffect.Readout(verdict: .lessOften, beforeHits: 4, beforeTotal: 5,
                                    afterHits: 1, afterTotal: 6)
        XCTAssertEqual(r.detail,
                       "In 4 of 5 swims before you started, 1 of 6 swims since.")
    }

    func testEveryInsufficientCaseHasDistinctCopy() {
        let cases: [DrillEffect.Missing] = [.neverPractised, .faultNotSeen,
                                            .tooFewBefore(have: 0), .tooFewBefore(have: 2),
                                            .tooFewAfter(have: 0), .tooFewAfter(have: 1)]
        var details: Set<String> = []
        for c in cases {
            XCTAssertFalse(c.headline.isEmpty)
            XCTAssertFalse(c.detail.isEmpty)
            details.insert(c.detail)
        }
        XCTAssertEqual(details.count, cases.count, "each case must say its own thing")
        XCTAssertEqual(DrillEffect.Missing.tooFewAfter(have: 1).detail,
                       "1 swim since you started this drill — 3 needed before a read-out.")
        XCTAssertEqual(DrillEffect.Missing.tooFewBefore(have: 2).detail,
                       "Only 2 swims on record from before you started this drill — 3 needed to compare against.")
    }

    // MARK: - Catalog integration

    func testEveryCatalogDrillCanProduceAReadout() {
        // Guards the fixes → issue-name contract: a drill whose `fixes`
        // drifted off the catalog would silently report "nothing to track"
        // forever.
        let known = Set(FeedbackEngine.issueNames)
        for drill in DrillCatalog.all {
            XCTAssertFalse(drill.fixes.isEmpty, "\(drill.id) targets nothing")
            for fix in drill.fixes {
                XCTAssertTrue(known.contains(fix), "\(drill.id) targets unknown fault \(fix)")
            }
            let swims = (1...3).map { swim(Double(-$0), [drill.fixes[0]]) }
                + (1...3).map { swim(Double($0), []) }
            guard case .measured(let r) = readout(fixes: drill.fixes, swims: swims)
            else { return XCTFail("\(drill.id) produced no read-out") }
            XCTAssertEqual(r.verdict, .lessOften)
        }
    }
}
