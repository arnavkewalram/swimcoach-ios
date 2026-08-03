import Foundation

/// Pure formatting behind `ShareCardView` — every string on the share card
/// is derived here so the card's content can be unit-tested without
/// rendering. Built from an `AnalysisResult` plus the saved session's
/// swimmer tag and name (empty strings when the session isn't saved).
struct ShareCardModel: Equatable, Sendable {

    struct IssueLine: Equatable, Sendable {
        let name: String
        let severity: TechniqueIssue.Severity
    }

    /// Most issues shown on the card — it's a headline, not the full report.
    static let maxIssues = 3

    let scoreText: String
    let grade: String
    let verdict: String
    /// Uppercased swimmer tag, nil when no swimmer is set.
    let swimmerTag: String?
    /// Session name as typed, nil when unnamed.
    let sessionName: String?
    let dateText: String
    /// "M:SS" clip length, nil for legacy sessions without a duration.
    let durationText: String?
    let strokesText: String
    /// Whole strokes-per-minute, nil without a duration.
    let strokeRateText: String?
    /// Highest-severity issues first (original order within a severity).
    let topIssues: [IssueLine]

    init(result: AnalysisResult, swimmer: String = "", sessionName: String = "") {
        scoreText = "\(result.score)"
        grade = result.grade
        verdict = Self.verdict(for: result.grade)

        let tag = swimmer.trimmingCharacters(in: .whitespacesAndNewlines)
        swimmerTag = tag.isEmpty ? nil : tag.uppercased()
        let name = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sessionName = name.isEmpty ? nil : name

        dateText = result.analyzedAt
            .formatted(date: .abbreviated, time: .omitted).uppercased()
        durationText = result.durationText
        strokesText = result.strokeCount > 0 ? "\(result.strokeCount)" : "–"
        strokeRateText = result.strokeRatePerMin.map { String(format: "%.0f", $0) }

        topIssues = result.issues.enumerated()
            .sorted { a, b in
                a.element.severity != b.element.severity
                    ? a.element.severity > b.element.severity
                    : a.offset < b.offset
            }
            .prefix(Self.maxIssues)
            .map { IssueLine(name: $0.element.displayName, severity: $0.element.severity) }
    }

    /// Share-sheet preview title.
    var previewTitle: String { "SwimCoach session — \(scoreText)/100 (\(grade))" }

    /// One-line reading of a grade — shared with `ResultsView`.
    static func verdict(for grade: String) -> String {
        switch grade {
        case "A": return "Excellent technique"
        case "B": return "Good form"
        case "C": return "Room to improve"
        case "D": return "Needs work"
        default:  return "Keep practicing"
        }
    }
}
