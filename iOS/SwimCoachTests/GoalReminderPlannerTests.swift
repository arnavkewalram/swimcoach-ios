import XCTest
@testable import SwimCoach

final class GoalReminderPlannerTests: XCTestCase {

    /// Fixed gregorian/UTC calendar so week boundaries never depend on
    /// the simulator's locale or timezone.
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 1   // weeks run Sunday → Saturday
        calendar = cal
    }

    override func tearDown() {
        calendar = nil
        super.tearDown()
    }

    /// 2026-07-22 is a Wednesday; its week runs Sun Jul 19 → Sat Jul 25.
    private func date(_ year: Int, _ month: Int, _ day: Int,
                      _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func fire(_ plan: GoalReminderPlanner.Plan) -> GoalReminderPlanner.Fire? {
        guard case .schedule(let f) = plan else { return nil }
        return f
    }

    // MARK: - Skip cases

    func testZeroGoalSkips() {
        // Arrange
        let now = date(2026, 7, 22, 10)

        // Act
        let plan = GoalReminderPlanner.plan(
            goal: 0, sessionsThisWeek: 2, weekday: 6, hour: 17, minute: 0,
            now: now, calendar: calendar)

        // Assert
        XCTAssertEqual(plan, .skip)
    }

    func testNegativeGoalSkips() {
        // Arrange
        let now = date(2026, 7, 22, 10)

        // Act
        let plan = GoalReminderPlanner.plan(
            goal: -1, sessionsThisWeek: 0, weekday: 6, hour: 17, minute: 0,
            now: now, calendar: calendar)

        // Assert
        XCTAssertEqual(plan, .skip)
    }

    // MARK: - Unmet goal, slot still ahead this week

    func testUnmetGoalSchedulesRepeatingAtChosenSlotThisWeek() {
        // Arrange — Wed morning, reminder Friday 17:00, 2 of 3 done
        let now = date(2026, 7, 22, 10)

        // Act
        let plan = GoalReminderPlanner.plan(
            goal: 3, sessionsThisWeek: 2, weekday: 6, hour: 17, minute: 0,
            now: now, calendar: calendar)

        // Assert — fires this Friday and keeps the weekly cadence
        let f = fire(plan)
        XCTAssertEqual(f?.date, date(2026, 7, 24, 17))
        XCTAssertEqual(f?.repeats, true)
        XCTAssertEqual(f?.title, "Weekly goal check")
        XCTAssertEqual(f?.body,
            "2 of 3 sessions logged this week — one more swim gets you there.")
    }

    func testFireDateCarriesChosenWeekdayHourAndMinute() {
        // Arrange — Monday 06:30 reminder chosen on a Wednesday
        let now = date(2026, 7, 22, 10)

        // Act
        let plan = GoalReminderPlanner.plan(
            goal: 3, sessionsThisWeek: 0, weekday: 2, hour: 6, minute: 30,
            now: now, calendar: calendar)

        // Assert
        let comps = calendar.dateComponents(
            [.weekday, .hour, .minute], from: fire(plan)!.date)
        XCTAssertEqual(comps.weekday, 2)
        XCTAssertEqual(comps.hour, 6)
        XCTAssertEqual(comps.minute, 30)
    }

    // MARK: - Copy variants

    func testCopyCountsRemainingSwimsWhenMoreThanOneLeft() {
        // Arrange
        let now = date(2026, 7, 22, 10)

        // Act
        let plan = GoalReminderPlanner.plan(
            goal: 4, sessionsThisWeek: 1, weekday: 6, hour: 17, minute: 0,
            now: now, calendar: calendar)

        // Assert
        XCTAssertEqual(fire(plan)?.body,
            "1 of 4 sessions logged this week — 3 more swims get you there.")
    }

    func testCopyForZeroSessionsAvoidsZeroOfY() {
        // Arrange
        let now = date(2026, 7, 22, 10)

        // Act
        let plan = GoalReminderPlanner.plan(
            goal: 3, sessionsThisWeek: 0, weekday: 6, hour: 17, minute: 0,
            now: now, calendar: calendar)

        // Assert
        XCTAssertEqual(fire(plan)?.body,
            "No sessions logged this week — 3 swims get you there.")
    }

    func testCopyForZeroSessionsWithSingleSessionGoalIsSingular() {
        // Arrange
        let now = date(2026, 7, 22, 10)

        // Act
        let plan = GoalReminderPlanner.plan(
            goal: 1, sessionsThisWeek: 0, weekday: 6, hour: 17, minute: 0,
            now: now, calendar: calendar)

        // Assert
        XCTAssertEqual(fire(plan)?.body,
            "No sessions logged this week — one swim gets you there.")
    }

    // MARK: - Slot already passed this week

    func testSlotAlreadyPassedRollsToNextWeekWithFreshWeekCopy() {
        // Arrange — Saturday morning, reminder was Friday 17:00
        let now = date(2026, 7, 25, 9)

        // Act
        let plan = GoalReminderPlanner.plan(
            goal: 3, sessionsThisWeek: 1, weekday: 6, hour: 17, minute: 0,
            now: now, calendar: calendar)

        // Assert — first fire is next Friday, in a fresh week: this week's
        // count is stale by then, so the copy must not quote it
        let f = fire(plan)
        XCTAssertEqual(f?.date, date(2026, 7, 31, 17))
        XCTAssertEqual(f?.repeats, true)
        XCTAssertEqual(f?.body, "New week on the sheet — 3 sessions to log.")
    }

    func testNowExactlyAtFireInstantRollsForwardAWeek() {
        // Arrange — now is precisely Friday 17:00
        let now = date(2026, 7, 24, 17)

        // Act
        let plan = GoalReminderPlanner.plan(
            goal: 3, sessionsThisWeek: 1, weekday: 6, hour: 17, minute: 0,
            now: now, calendar: calendar)

        // Assert — never schedules a fire in the past or the same instant
        XCTAssertEqual(fire(plan)?.date, date(2026, 7, 31, 17))
    }

    // MARK: - Met goal

    func testMetGoalSkipsCurrentWeekWithOneShotAtNextWeeksSlot() {
        // Arrange — Wed, 3 of 3 done, reminder would fire this Friday
        let now = date(2026, 7, 22, 10)

        // Act
        let plan = GoalReminderPlanner.plan(
            goal: 3, sessionsThisWeek: 3, weekday: 6, hour: 17, minute: 0,
            now: now, calendar: calendar)

        // Assert — one-shot NEXT Friday; the next app open re-arms the
        // repeating cadence, so no nag lands in the already-met week
        let f = fire(plan)
        XCTAssertEqual(f?.date, date(2026, 7, 31, 17))
        XCTAssertEqual(f?.repeats, false)
        XCTAssertEqual(f?.body, "New week on the sheet — 3 sessions to log.")
    }

    func testOverachievedGoalAlsoSkipsCurrentWeek() {
        // Arrange — 5 sessions against a goal of 3
        let now = date(2026, 7, 22, 10)

        // Act
        let plan = GoalReminderPlanner.plan(
            goal: 3, sessionsThisWeek: 5, weekday: 6, hour: 17, minute: 0,
            now: now, calendar: calendar)

        // Assert
        let f = fire(plan)
        XCTAssertEqual(f?.date, date(2026, 7, 31, 17))
        XCTAssertEqual(f?.repeats, false)
    }

    func testMetGoalWithSlotAlreadyPassedKeepsRepeatingCadence() {
        // Arrange — Saturday after a met week; next Friday is already in a
        // fresh week, so nothing needs skipping
        let now = date(2026, 7, 25, 9)

        // Act
        let plan = GoalReminderPlanner.plan(
            goal: 3, sessionsThisWeek: 3, weekday: 6, hour: 17, minute: 0,
            now: now, calendar: calendar)

        // Assert
        let f = fire(plan)
        XCTAssertEqual(f?.date, date(2026, 7, 31, 17))
        XCTAssertEqual(f?.repeats, true)
        XCTAssertEqual(f?.body, "New week on the sheet — 3 sessions to log.")
    }

    func testFreshWeekCopyIsSingularForSingleSessionGoal() {
        // Arrange — goal of 1, already met this week
        let now = date(2026, 7, 22, 10)

        // Act
        let plan = GoalReminderPlanner.plan(
            goal: 1, sessionsThisWeek: 1, weekday: 6, hour: 17, minute: 0,
            now: now, calendar: calendar)

        // Assert
        XCTAssertEqual(fire(plan)?.body,
            "New week on the sheet — one session to log.")
    }

    // MARK: - Calendar sensitivity

    func testMondayFirstWeekdayCalendarStillSkipsMetWeekCorrectly() {
        // Arrange — EU-style Monday-start weeks: Sun Jul 26 belongs to the
        // week of Mon Jul 20 … Sun Jul 26. Reminder Sunday 18:00, met goal.
        var cal = calendar!
        cal.firstWeekday = 2
        let now = date(2026, 7, 22, 10)

        // Act
        let plan = GoalReminderPlanner.plan(
            goal: 2, sessionsThisWeek: 2, weekday: 1, hour: 18, minute: 0,
            now: now, calendar: cal)

        // Assert — Sun Jul 26 18:00 is inside the met week, so the one-shot
        // lands a week later
        let f = fire(plan)
        XCTAssertEqual(f?.date, date(2026, 8, 2, 18))
        XCTAssertEqual(f?.repeats, false)
    }
}
