import Foundation

/// Per-swimmer weekly session goals. The Everyone scope ("") keeps the
/// original global "weeklyGoal" key, so a goal set before swimmer scoping
/// existed migrates for free. Named swimmers share one dictionary under
/// "weeklyGoalBySwimmer". A swimmer with no explicit goal inherits the
/// Everyone goal; an explicit 0 ("off") beats that fallback so a swimmer
/// can opt out of a shared goal. Resolution and updates are pure static
/// functions; the instance is a thin UserDefaults shell around them.
struct WeeklyGoalStore {

    static let everyoneKey = "weeklyGoal"
    static let swimmersKey = "weeklyGoalBySwimmer"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Pure core

    /// Resolved goal for a swimmer: their explicit entry when present,
    /// otherwise the Everyone goal. "" is the Everyone scope itself.
    static func resolve(swimmer: String, everyoneGoal: Int,
                        swimmerGoals: [String: Int]) -> Int {
        guard !swimmer.isEmpty else { return everyoneGoal }
        return swimmerGoals[swimmer] ?? everyoneGoal
    }

    /// New dictionary with `goal` recorded for `swimmer`. The input is
    /// untouched. Everyone ("") lives outside the dictionary, so it
    /// passes through unchanged.
    static func updating(_ goals: [String: Int], swimmer: String,
                         goal: Int) -> [String: Int] {
        guard !swimmer.isEmpty else { return goals }
        return goals.merging([swimmer: goal]) { _, new in new }
    }

    // MARK: - Persistence

    /// Goal shown for `swimmer`, fallback applied. 0 means no goal.
    func goal(for swimmer: String) -> Int {
        Self.resolve(swimmer: swimmer,
                     everyoneGoal: defaults.integer(forKey: Self.everyoneKey),
                     swimmerGoals: swimmerGoals)
    }

    /// Records `goal` for `swimmer`; "" writes the legacy global key.
    func setGoal(_ goal: Int, for swimmer: String) {
        if swimmer.isEmpty {
            defaults.set(goal, forKey: Self.everyoneKey)
        } else {
            defaults.set(Self.updating(swimmerGoals, swimmer: swimmer, goal: goal),
                         forKey: Self.swimmersKey)
        }
    }

    /// Stored per-swimmer goals; entries that aren't Ints (corrupt or
    /// hand-edited plists) are dropped rather than trusted.
    private var swimmerGoals: [String: Int] {
        (defaults.dictionary(forKey: Self.swimmersKey) ?? [:])
            .compactMapValues { $0 as? Int }
    }
}
