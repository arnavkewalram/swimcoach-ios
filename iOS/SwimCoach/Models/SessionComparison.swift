import Foundation

/// Per-issue verdict between two sessions — the "am I improving?" answer.
struct IssueDelta: Hashable, Identifiable {
    enum Verdict: String {
        case new = "NEW"
        case resolved = "RESOLVED"
        case improved = "IMPROVED"
        case worsened = "WORSE"
        case unchanged = "SAME"
    }

    let name: String
    let displayName: String
    /// Model probability in the earlier / later session (nil = not detected).
    let from: Double?
    let to: Double?
    let verdict: Verdict

    var id: String { name }
}

enum SessionComparison {
    /// Probability change below this reads as "unchanged" — model noise,
    /// not progress.
    static let changeThreshold = 0.10

    /// Compare detected issues of an earlier session against a later one.
    /// Ordered: worsened & new first (needs attention), then improved,
    /// resolved, unchanged.
    static func issueDeltas(from earlier: AnalysisResult, to later: AnalysisResult) -> [IssueDelta] {
        let fromMap = Dictionary(uniqueKeysWithValues: earlier.issues.map { ($0.name, $0) })
        let toMap = Dictionary(uniqueKeysWithValues: later.issues.map { ($0.name, $0) })
        let names = Array(Set(fromMap.keys).union(toMap.keys))

        let deltas = names.map { name -> IssueDelta in
            let f = fromMap[name]
            let t = toMap[name]
            let display = t?.displayName ?? f?.displayName ?? name
            switch (f, t) {
            case (nil, let t?):
                return IssueDelta(name: name, displayName: display,
                                  from: nil, to: t.observedValue, verdict: .new)
            case (let f?, nil):
                return IssueDelta(name: name, displayName: display,
                                  from: f.observedValue, to: nil, verdict: .resolved)
            case (let f?, let t?):
                let change = t.observedValue - f.observedValue
                let verdict: IssueDelta.Verdict =
                    change <= -changeThreshold ? .improved :
                    change >= changeThreshold ? .worsened : .unchanged
                return IssueDelta(name: name, displayName: display,
                                  from: f.observedValue, to: t.observedValue, verdict: verdict)
            case (nil, nil):
                return IssueDelta(name: name, displayName: display,
                                  from: nil, to: nil, verdict: .unchanged)
            }
        }

        let rank: [IssueDelta.Verdict: Int] = [.worsened: 0, .new: 1, .improved: 2,
                                               .resolved: 3, .unchanged: 4]
        return deltas.sorted {
            (rank[$0.verdict] ?? 9, $0.displayName) < (rank[$1.verdict] ?? 9, $1.displayName)
        }
    }
}
