import Foundation

/// Pure matching logic behind History search — testable without SwiftData.
enum SessionFilter {

    /// Case-insensitive substring match across name, notes, and the row's
    /// date text. An empty (or whitespace) query matches everything.
    static func matches(query: String, name: String, notes: String, dateText: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return name.localizedCaseInsensitiveContains(q)
            || notes.localizedCaseInsensitiveContains(q)
            || dateText.localizedCaseInsensitiveContains(q)
    }

    /// Grade-chip filter: an empty selection means "all grades".
    static func matches(grades: Set<String>, grade: String) -> Bool {
        grades.isEmpty || grades.contains(grade)
    }
}
