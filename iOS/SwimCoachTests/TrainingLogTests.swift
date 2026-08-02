import XCTest
@testable import SwimCoach

final class TrainingLogTests: XCTestCase {

    // Fixed calendar so week boundaries don't drift with the runner's locale
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2   // Monday
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testWeekSummaryCountsOnlyThatWeek() {
        // Mon 2026-07-27 … Sun 2026-08-02 is one week
        let entries = [
            TrainingLog.Entry(date: date(2026, 7, 26), score: 50),  // previous week
            TrainingLog.Entry(date: date(2026, 7, 27), score: 60),
            TrainingLog.Entry(date: date(2026, 8, 1), score: 70),
            TrainingLog.Entry(date: date(2026, 8, 3), score: 90),   // next week
        ]
        let summary = TrainingLog.summary(
            for: entries, weekContaining: date(2026, 7, 29), calendar: cal)
        XCTAssertEqual(summary, TrainingLog.WeekSummary(sessionCount: 2, averageScore: 65))
    }

    func testWeekSummaryEmptyWeekIsZero() {
        let entries = [TrainingLog.Entry(date: date(2026, 7, 1), score: 80)]
        let summary = TrainingLog.summary(
            for: entries, weekContaining: date(2026, 8, 1), calendar: cal)
        XCTAssertEqual(summary.sessionCount, 0)
        XCTAssertEqual(summary.averageScore, 0)
    }

    func testWeekOverWeekDelta() {
        let entries = [
            TrainingLog.Entry(date: date(2026, 7, 22), score: 60),  // last week (Wed)
            TrainingLog.Entry(date: date(2026, 7, 24), score: 62),  // last week (Fri)
            TrainingLog.Entry(date: date(2026, 7, 28), score: 70),  // this week (Tue)
        ]
        let delta = TrainingLog.weekOverWeekDelta(
            for: entries, now: date(2026, 7, 29), calendar: cal)
        XCTAssertEqual(delta, 9)   // 70 - (60+62)/2
    }

    func testWeekOverWeekDeltaNilWhenAWeekIsEmpty() {
        let onlyThisWeek = [TrainingLog.Entry(date: date(2026, 7, 28), score: 70)]
        XCTAssertNil(TrainingLog.weekOverWeekDelta(
            for: onlyThisWeek, now: date(2026, 7, 29), calendar: cal))
        XCTAssertNil(TrainingLog.weekOverWeekDelta(
            for: [], now: date(2026, 7, 29), calendar: cal))
    }

    func testRecentScoresChronologicalAndCapped() {
        // Deliberately unsorted input
        let entries = (1...12).shuffled().map {
            TrainingLog.Entry(date: date(2026, 7, $0), score: $0 * 5)
        }
        let scores = TrainingLog.recentScores(from: entries, limit: 10)
        XCTAssertEqual(scores, [15, 20, 25, 30, 35, 40, 45, 50, 55, 60])
    }

    func testWeeklyCountsChronologicalWithGaps() {
        // Sessions in the current week and three weeks back; gap between
        let now = date(2026, 7, 29)
        let entries = [
            TrainingLog.Entry(date: date(2026, 7, 28), score: 70),   // this week
            TrainingLog.Entry(date: date(2026, 7, 27), score: 68),   // this week
            TrainingLog.Entry(date: date(2026, 7, 8), score: 60),    // 3 weeks back
        ]
        let counts = TrainingLog.weeklyCounts(for: entries, weeks: 4, now: now, calendar: cal)
        XCTAssertEqual(counts, [1, 0, 0, 2])
    }

    func testWeeklyCountsEmptyAndZeroWeeks() {
        XCTAssertEqual(TrainingLog.weeklyCounts(for: [], weeks: 3,
                                                now: date(2026, 7, 29), calendar: cal),
                       [0, 0, 0])
        XCTAssertEqual(TrainingLog.weeklyCounts(for: [], weeks: 0,
                                                now: date(2026, 7, 29), calendar: cal), [])
    }

    func testWeeklyStreakCountsConsecutiveWeeks() {
        let now = date(2026, 7, 29)
        let entries = [
            TrainingLog.Entry(date: date(2026, 7, 28), score: 70),   // this week
            TrainingLog.Entry(date: date(2026, 7, 21), score: 68),   // -1 week
            TrainingLog.Entry(date: date(2026, 7, 14), score: 66),   // -2 weeks
            TrainingLog.Entry(date: date(2026, 6, 30), score: 60),   // -4 weeks (gap at -3)
        ]
        XCTAssertEqual(TrainingLog.weeklyStreak(for: entries, now: now, calendar: cal), 3)
    }

    func testWeeklyStreakGraceForQuietCurrentWeek() {
        let now = date(2026, 7, 29)
        let entries = [
            TrainingLog.Entry(date: date(2026, 7, 21), score: 68),   // -1 week
            TrainingLog.Entry(date: date(2026, 7, 14), score: 66),   // -2 weeks
        ]
        // Nothing yet this week — the run ending last week still stands
        XCTAssertEqual(TrainingLog.weeklyStreak(for: entries, now: now, calendar: cal), 2)
    }

    func testWeeklyStreakZeroAfterFullGap() {
        let now = date(2026, 7, 29)
        let entries = [TrainingLog.Entry(date: date(2026, 7, 7), score: 66)]  // -3 weeks
        XCTAssertEqual(TrainingLog.weeklyStreak(for: entries, now: now, calendar: cal), 0)
        XCTAssertEqual(TrainingLog.weeklyStreak(for: [], now: now, calendar: cal), 0)
    }

    func testIsNewBest() {
        XCTAssertFalse(TrainingLog.isNewBest(score: 90, priorBest: nil),
                       "first session ever has nothing to beat")
        XCTAssertFalse(TrainingLog.isNewBest(score: 70, priorBest: 70), "tie is not a new best")
        XCTAssertFalse(TrainingLog.isNewBest(score: 65, priorBest: 70))
        XCTAssertTrue(TrainingLog.isNewBest(score: 71, priorBest: 70))
    }

    func testWhatsNewShowLogic() {
        XCTAssertFalse(WhatsNew.shouldShow(current: "1.26.0", lastSeen: ""),
                       "fresh installs get onboarding, not release notes")
        XCTAssertFalse(WhatsNew.shouldShow(current: "1.26.0", lastSeen: "1.26.0"))
        XCTAssertTrue(WhatsNew.shouldShow(current: "1.26.0", lastSeen: "1.25.1"))
    }

    func testWhatsNewHighlightsWellFormed() {
        XCTAssertFalse(WhatsNew.highlights.isEmpty)
        XCTAssertTrue(WhatsNew.highlights.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
        XCTAssertEqual(WhatsNew.highlights.map(\.id).count,
                       Set(WhatsNew.highlights.map(\.id)).count, "titles must be unique ids")
    }

    func testPrivacyManifestIsBundled() {
        // Apple requires PrivacyInfo.xcprivacy in App Store binaries.
        XCTAssertNotNil(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
    }

    func testFontLicenseIsBundled() {
        // The OFL obliges shipping the license with the fonts; AboutView
        // renders it from the bundle.
        XCTAssertNotNil(Bundle.main.url(forResource: "OFL", withExtension: "txt"))
    }

    func testGoalTicksNilWhenNoGoal() {
        XCTAssertNil(TrainingLog.goalTicks(sessionCount: 5, goal: 0))
        XCTAssertNil(TrainingLog.goalTicks(sessionCount: 5, goal: -1))
    }

    func testGoalTicksPartialAndMet() {
        let partial = TrainingLog.goalTicks(sessionCount: 2, goal: 3)
        XCTAssertEqual(partial, TrainingLog.GoalTicks(filled: 2, total: 3, overflow: 0))
        XCTAssertFalse(partial?.isMet ?? true)

        let met = TrainingLog.goalTicks(sessionCount: 3, goal: 3)
        XCTAssertTrue(met?.isMet ?? false)
    }

    func testGoalTicksOverflowAndNegativeCount() {
        let over = TrainingLog.goalTicks(sessionCount: 5, goal: 3)
        XCTAssertEqual(over, TrainingLog.GoalTicks(filled: 3, total: 3, overflow: 2))
        XCTAssertTrue(over?.isMet ?? false)

        let negative = TrainingLog.goalTicks(sessionCount: -2, goal: 3)
        XCTAssertEqual(negative, TrainingLog.GoalTicks(filled: 0, total: 3, overflow: 0))
    }

    func testSparklinePointsNormalization() {
        let size = CGSize(width: 100, height: 50)
        let pts = Sparkline.points(for: [50, 100, 75], in: size)
        XCTAssertEqual(pts.count, 3)
        XCTAssertEqual(pts[0].x, 0);  XCTAssertEqual(pts[2].x, 100)
        // Higher score → smaller y (top-left origin); min/max keep headroom
        XCTAssertLessThan(pts[1].y, pts[0].y)
        XCTAssertEqual(pts[0].y, 50 * (1 - 0.15), accuracy: 0.001)
        XCTAssertEqual(pts[1].y, 50 * (1 - 0.85), accuracy: 0.001)
    }

    func testSparklineSingleValueCentersDot() {
        let pts = Sparkline.points(for: [70], in: CGSize(width: 100, height: 50))
        XCTAssertEqual(pts.count, 1)
        XCTAssertEqual(pts[0].x, 50)
    }
}
