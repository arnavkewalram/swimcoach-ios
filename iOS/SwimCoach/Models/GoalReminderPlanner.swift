import Foundation

/// Pure decision core for the weekly goal reminder. Given the resolved
/// goal, the live session count for the current week, and the chosen
/// day/time, it decides whether a notification should be pending and
/// with what fire date and copy. UNUserNotificationCenter never appears
/// here — `GoalReminderScheduler` translates the plan into a request —
/// so every branch unit-tests with injected dates.
enum GoalReminderPlanner {

    /// A pending notification: when it fires, whether it repeats weekly,
    /// and the exact copy. `repeats` is false only when a met goal forces
    /// a one-shot that skips the current week; the next reschedule (app
    /// activation or session save) restores the weekly cadence.
    struct Fire: Equatable {
        let date: Date
        let repeats: Bool
        let title: String
        let body: String
    }

    enum Plan: Equatable {
        /// No pending request should exist (no goal set).
        case skip
        case schedule(Fire)
    }

    static let title = "Weekly goal check"

    /// Decide the reminder state. `weekday` uses Calendar numbering
    /// (1 = Sunday … 7 = Saturday). The caller guarantees the reminder
    /// is enabled; a disabled reminder is a plain cancel upstream.
    static func plan(goal: Int, sessionsThisWeek: Int,
                     weekday: Int, hour: Int, minute: Int,
                     now: Date, calendar: Calendar = .current) -> Plan {
        guard goal > 0 else { return .skip }

        let match = DateComponents(hour: hour, minute: minute, weekday: weekday)
        guard let next = calendar.nextDate(after: now, matching: match,
                                           matchingPolicy: .nextTime),
              let week = calendar.dateInterval(of: .weekOfYear, for: now)
        else { return .skip }

        let isMet = sessionsThisWeek >= goal

        guard week.contains(next) else {
            // The chosen slot already passed this week — the first fire
            // lands in a fresh week either way, met or not.
            return .schedule(Fire(date: next, repeats: true, title: title,
                                  body: freshWeekBody(goal: goal)))
        }
        guard isMet else {
            return .schedule(Fire(date: next, repeats: true, title: title,
                                  body: progressBody(count: sessionsThisWeek,
                                                     goal: goal)))
        }
        // Goal already met: a repeating trigger would still nag this week,
        // so skip it with a one-shot at next week's slot.
        guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1,
                                           to: next) else { return .skip }
        return .schedule(Fire(date: nextWeek, repeats: false, title: title,
                              body: freshWeekBody(goal: goal)))
    }

    // MARK: - Copy

    /// Mid-week nudge with the live count.
    static func progressBody(count: Int, goal: Int) -> String {
        guard count > 0 else {
            return goal == 1
                ? "No sessions logged this week — one swim gets you there."
                : "No sessions logged this week — \(goal) swims get you there."
        }
        let remaining = max(1, goal - count)
        return remaining == 1
            ? "\(count) of \(goal) sessions logged this week — one more swim gets you there."
            : "\(count) of \(goal) sessions logged this week — \(remaining) more swims get you there."
    }

    /// Copy for a fire that lands in a week that hasn't started yet.
    static func freshWeekBody(goal: Int) -> String {
        goal == 1
            ? "New week on the sheet — one session to log."
            : "New week on the sheet — \(goal) sessions to log."
    }
}
