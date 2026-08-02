import Foundation

/// Pure aggregation over saved-session (date, score) pairs — the data
/// behind the Home training log. Kept SwiftData-free so it unit-tests.
enum TrainingLog {

    struct Entry: Equatable {
        let date: Date
        let score: Int
    }

    struct WeekSummary: Equatable {
        let sessionCount: Int
        let averageScore: Int
    }

    /// Sessions and average score in the calendar week containing `ref`.
    static func summary(for entries: [Entry], weekContaining ref: Date,
                        calendar: Calendar = .current) -> WeekSummary {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: ref) else {
            return WeekSummary(sessionCount: 0, averageScore: 0)
        }
        let scores = entries.filter { week.contains($0.date) }.map(\.score)
        guard !scores.isEmpty else {
            return WeekSummary(sessionCount: 0, averageScore: 0)
        }
        return WeekSummary(sessionCount: scores.count,
                           averageScore: scores.reduce(0, +) / scores.count)
    }

    /// Average-score change vs the previous calendar week. Nil unless both
    /// weeks have at least one session — a delta against nothing is noise.
    static func weekOverWeekDelta(for entries: [Entry], now: Date = Date(),
                                  calendar: Calendar = .current) -> Int? {
        guard let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now) else {
            return nil
        }
        let this = summary(for: entries, weekContaining: now, calendar: calendar)
        let prev = summary(for: entries, weekContaining: lastWeek, calendar: calendar)
        guard this.sessionCount > 0, prev.sessionCount > 0 else { return nil }
        return this.averageScore - prev.averageScore
    }

    /// The most recent `limit` scores in chronological order — sparkline input.
    static func recentScores(from entries: [Entry], limit: Int = 10) -> [Int] {
        Array(entries.sorted { $0.date < $1.date }.suffix(limit).map(\.score))
    }

    /// True when a score beats every prior session. Nil prior best (first
    /// session ever) is not a "new best" — there was nothing to beat.
    static func isNewBest(score: Int, priorBest: Int?) -> Bool {
        guard let prior = priorBest else { return false }
        return score > prior
    }

    struct GoalTicks: Equatable {
        let filled: Int     // sessions done, capped at the goal
        let total: Int      // the goal itself
        let overflow: Int   // sessions beyond the goal
        var isMet: Bool { filled >= total }
    }

    /// Tick-row state for a weekly session goal. Nil when no goal is set
    /// (goal <= 0) — the UI shows the set-goal affordance instead.
    static func goalTicks(sessionCount: Int, goal: Int) -> GoalTicks? {
        guard goal > 0 else { return nil }
        let count = max(0, sessionCount)
        return GoalTicks(filled: min(count, goal),
                         total: goal,
                         overflow: max(0, count - goal))
    }
}
