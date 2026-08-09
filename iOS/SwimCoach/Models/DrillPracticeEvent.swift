import Foundation
import SwiftData

/// One "I did this drill" tap — the drill library's practice memory.
@Model
final class DrillPracticeEvent {
    var drillID: String
    var date: Date
    /// Who tapped, stamped from `activeSwimmer`. Empty means untagged —
    /// the same shape and the same meaning as `SwimSession.swimmer`, and
    /// what every tap recorded before this column existed migrates in as
    /// (defaulted, so the SwiftData migration is lossless). `DrillEffect`
    /// owns what an untagged tap counts for; see its doc.
    var swimmer: String = ""

    init(drillID: String, date: Date = Date(), swimmer: String = "") {
        self.drillID = drillID
        self.date = date
        self.swimmer = swimmer
    }
}

/// Pure practice-summary math over fetched events — unit-tested.
enum DrillPractice {
    struct Summary: Equatable {
        let count: Int
        let lastDate: Date?
    }

    /// The taps that count inside `scope`, by `DrillEffect`'s one ownership
    /// rule — so the card's PRACTICED tally, its START HERE pick and its
    /// read-out are all describing the same swimmer's practice.
    static func scoped(_ events: [DrillPracticeEvent], to scope: String) -> [DrillPracticeEvent] {
        events.filter { DrillEffect.belongs($0.swimmer, to: scope) }
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
