import Foundation
import SwiftData
import UserNotifications

/// Thin UNUserNotificationCenter shell around GoalReminderPlanner output.
/// All decisions (fire date, copy, skip-a-met-week) happen in the pure
/// planner; this type only translates a Plan into the single pending
/// request and owns the authorization prompt.
struct GoalReminderScheduler {

    /// One reminder exists at a time — re-adding under the same identifier
    /// replaces the pending request, which is how copy stays fresh.
    static let requestID = "weeklyGoalReminder"

    /// Full (not provisional) authorization: the reminder is opt-in, so
    /// the prompt appears only when the user first flips the toggle on.
    /// Returns false on denial or error; the caller keeps the toggle off.
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// True when the user has revoked notification permission after
    /// enabling the reminder — the sheet flips the toggle back off.
    func isDenied() async -> Bool {
        await UNUserNotificationCenter.current()
            .notificationSettings().authorizationStatus == .denied
    }

    /// Replaces the pending reminder with `plan`. A repeating fire matches
    /// weekday+hour+minute (weekly cadence); a one-shot pins the full date
    /// so a met week is skipped instead of nagged.
    func apply(_ plan: GoalReminderPlanner.Plan, calendar: Calendar = .current) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
        guard case .schedule(let fire) = plan else { return }

        let content = UNMutableNotificationContent()
        content.title = fire.title
        content.body = fire.body
        content.sound = .default

        let components = fire.repeats
            ? calendar.dateComponents([.weekday, .hour, .minute], from: fire.date)
            : calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                      from: fire.date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components,
                                                    repeats: fire.repeats)
        center.add(UNNotificationRequest(identifier: Self.requestID,
                                         content: content, trigger: trigger)) { error in
            if let error {
                AppLog.storage.error(
                    "Goal reminder scheduling failed: \(error.localizedDescription)")
            }
        }
    }

    func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.requestID])
    }
}

/// Recomputes the reminder from live data and re-arms (or cancels) the
/// pending request. Called on scene activation and after a session save,
/// so the notification copy always matches the training log — a
/// UNCalendarNotificationTrigger can't know the live count on its own.
enum GoalReminder {

    @MainActor
    static func reschedule(context: ModelContext,
                           defaults: UserDefaults = .standard,
                           now: Date = Date(),
                           calendar: Calendar = .current) {
        let swimmer = defaults.string(forKey: "activeSwimmer") ?? ""
        let scheduler = GoalReminderScheduler()
        let settings = GoalReminderStore(defaults: defaults).settings(for: swimmer)
        guard settings.isEnabled else {
            scheduler.cancel()
            return
        }

        let goal = WeeklyGoalStore(defaults: defaults).goal(for: swimmer)
        let sessions = (try? context.fetch(FetchDescriptor<SwimSession>())) ?? []
        // Same scoping rule as HomeView: a named swimmer with no sessions
        // at all falls back to everyone, so the reminder counts exactly
        // what the training log panel shows.
        let scoped: [SwimSession]
        if swimmer.isEmpty {
            scoped = sessions
        } else {
            let mine = sessions.filter { $0.swimmer == swimmer }
            scoped = mine.isEmpty ? sessions : mine
        }
        let thisWeek = TrainingLog.summary(
            for: scoped.map { TrainingLog.Entry(date: $0.analyzedAt, score: $0.score) },
            weekContaining: now, calendar: calendar).sessionCount

        scheduler.apply(
            GoalReminderPlanner.plan(goal: goal, sessionsThisWeek: thisWeek,
                                     weekday: settings.weekday,
                                     hour: settings.hour,
                                     minute: settings.minute,
                                     now: now, calendar: calendar),
            calendar: calendar)
    }
}
