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
}
