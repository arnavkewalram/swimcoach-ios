import Foundation

/// Picks the fault most worth practicing right now. Pure — unit-tested.
enum FocusFault {

    /// Sessions to look back over.
    static let window = 5
    /// A fault must recur to be a focus — one-offs are noise.
    static let minOccurrences = 2

    /// `recentIssueNames` is chronological (oldest first), one array of
    /// fault names per session. Returns the fault name to focus on, or
    /// nil when nothing recurs in the window.
    static func pick(recentIssueNames: [[String]]) -> String? {
        let windowed = Array(recentIssueNames.suffix(window))
        guard !windowed.isEmpty else { return nil }

        var counts: [String: Int] = [:]
        var lastSeen: [String: Int] = [:]
        for (i, names) in windowed.enumerated() {
            for name in Set(names) {
                counts[name, default: 0] += 1
                lastSeen[name] = i
            }
        }
        return counts
            .filter { $0.value >= minOccurrences }
            .sorted { a, b in
                if a.value != b.value { return a.value > b.value }          // most frequent
                let la = lastSeen[a.key] ?? -1, lb = lastSeen[b.key] ?? -1
                if la != lb { return la > lb }                              // most recent
                return a.key < b.key                                        // deterministic
            }
            .first?.key
    }

    /// Occurrence count of a fault within the window.
    static func occurrences(of name: String, in recentIssueNames: [[String]]) -> Int {
        recentIssueNames.suffix(window).filter { $0.contains(name) }.count
    }
}
