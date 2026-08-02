import Foundation
import SwiftData

/// One "I did this drill" tap — the drill library's practice memory.
@Model
final class DrillPracticeEvent {
    var drillID: String
    var date: Date

    init(drillID: String, date: Date = Date()) {
        self.drillID = drillID
        self.date = date
    }
}

/// Pure practice-summary math over fetched events — unit-tested.
enum DrillPractice {
    struct Summary: Equatable {
        let count: Int
        let lastDate: Date?
    }

    static func summary(for drillID: String, events: [DrillPracticeEvent]) -> Summary {
        let mine = events.filter { $0.drillID == drillID }
        return Summary(count: mine.count, lastDate: mine.map(\.date).max())
    }

    /// The drill most due for practice: never-practiced first (in given
    /// order), then the one practiced longest ago.
    static func leastRecentlyPracticed(of drillIDs: [String],
                                       events: [DrillPracticeEvent]) -> String? {
        guard !drillIDs.isEmpty else { return nil }
        let lastDates = drillIDs.map { (id: $0, last: summary(for: $0, events: events).lastDate) }
        if let never = lastDates.first(where: { $0.last == nil }) { return never.id }
        return lastDates.min { ($0.last ?? .distantPast) < ($1.last ?? .distantPast) }?.id
    }
}
