import Foundation

/// Direction of a recurring fault across sessions. Pure — unit-tested.
enum IssueTrend: Equatable {
    case improving   // appearing less in recent sessions
    case worsening   // appearing more
    case flat

    /// Minimum sessions before a trend is worth claiming.
    static let minSessions = 6
    /// Rate change (recent half vs earlier half) that counts as movement.
    static let threshold = 0.25

    /// `occurrences` is chronological presence flags for one fault —
    /// true where the session contained it.
    static func trend(occurrences: [Bool]) -> IssueTrend {
        guard occurrences.count >= minSessions else { return .flat }
        let half = occurrences.count / 2
        let earlier = occurrences.prefix(occurrences.count - half)
        let recent = occurrences.suffix(half)
        let earlierRate = Double(earlier.filter { $0 }.count) / Double(earlier.count)
        let recentRate = Double(recent.filter { $0 }.count) / Double(recent.count)
        let delta = recentRate - earlierRate
        if delta <= -threshold { return .improving }
        if delta >= threshold { return .worsening }
        return .flat
    }
}
