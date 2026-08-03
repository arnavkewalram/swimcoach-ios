import Foundation

/// Per-swimmer weekly goal reminder settings, shaped like WeeklyGoalStore:
/// the Everyone scope ("") lives on its own key, named swimmers share one
/// dictionary, and a swimmer with no explicit entry inherits the Everyone
/// settings (an explicit disabled entry beats that fallback). Resolution,
/// updates, and codec are pure statics; the instance is a thin
/// UserDefaults shell around them.
struct GoalReminderStore {

    static let everyoneKey = "goalReminder"
    static let swimmersKey = "goalReminderBySwimmer"

    /// One scope's reminder choice. Defaults to off, Friday 17:00 —
    /// `weekday` uses Calendar numbering (1 = Sunday … 7 = Saturday).
    struct Settings: Equatable {
        var isEnabled = false
        var weekday = 6
        var hour = 17
        var minute = 0

        static let initial = Settings()
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Pure core

    /// Resolved settings for a swimmer: their explicit entry when present,
    /// otherwise the Everyone settings, otherwise the defaults.
    static func resolve(swimmer: String, everyone: Settings?,
                        bySwimmer: [String: Settings]) -> Settings {
        guard !swimmer.isEmpty else { return everyone ?? .initial }
        return bySwimmer[swimmer] ?? everyone ?? .initial
    }

    /// New dictionary with `settings` recorded for `swimmer`; the input is
    /// untouched. Everyone ("") lives outside the dictionary, so it passes
    /// through unchanged.
    static func updating(_ all: [String: Settings], swimmer: String,
                         settings: Settings) -> [String: Settings] {
        guard !swimmer.isEmpty else { return all }
        return all.merging([swimmer: settings]) { _, new in new }
    }

    /// Plist-friendly encoding (Ints only — no NSCoding surprises).
    static func encode(_ settings: Settings) -> [String: Int] {
        ["enabled": settings.isEnabled ? 1 : 0,
         "weekday": settings.weekday,
         "hour": settings.hour,
         "minute": settings.minute]
    }

    /// Strict decode: corrupt or out-of-range entries (hand-edited plists,
    /// future format drift) yield nil rather than a half-trusted value.
    static func decode(_ dict: [String: Any]?) -> Settings? {
        guard let dict,
              let enabled = dict["enabled"] as? Int,
              let weekday = dict["weekday"] as? Int, (1...7).contains(weekday),
              let hour = dict["hour"] as? Int, (0...23).contains(hour),
              let minute = dict["minute"] as? Int, (0...59).contains(minute)
        else { return nil }
        return Settings(isEnabled: enabled != 0, weekday: weekday,
                        hour: hour, minute: minute)
    }

    // MARK: - Persistence

    /// Settings shown for `swimmer`, fallback applied.
    func settings(for swimmer: String) -> Settings {
        Self.resolve(swimmer: swimmer,
                     everyone: Self.decode(defaults.dictionary(forKey: Self.everyoneKey)),
                     bySwimmer: swimmerSettings)
    }

    /// Records `settings` for `swimmer`; "" writes the Everyone key.
    func setSettings(_ settings: Settings, for swimmer: String) {
        if swimmer.isEmpty {
            defaults.set(Self.encode(settings), forKey: Self.everyoneKey)
        } else {
            let updated = Self.updating(swimmerSettings, swimmer: swimmer,
                                        settings: settings)
            defaults.set(updated.mapValues(Self.encode),
                         forKey: Self.swimmersKey)
        }
    }

    /// Stored per-swimmer settings; undecodable entries are dropped.
    private var swimmerSettings: [String: Settings] {
        (defaults.dictionary(forKey: Self.swimmersKey) ?? [:])
            .compactMapValues { Self.decode($0 as? [String: Any]) }
    }
}
