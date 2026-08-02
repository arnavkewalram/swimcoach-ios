import Foundation

/// Per-window model output with its source-time span — the data behind the
/// issue timeline and "see it" seeking. `probs` is in FeedbackEngine catalog
/// order (== ISSUE_LABELS order in ml/model.py).
struct IssueWindow: Hashable, Codable, Sendable {
    let start: Double
    let end: Double
    let probs: [Float]
}

extension [IssueWindow] {
    /// The window where a given label peaked — where to seek for "see it".
    func peakWindow(labelIndex: Int) -> IssueWindow? {
        guard !isEmpty, labelIndex >= 0 else { return nil }
        return self.filter { $0.probs.indices.contains(labelIndex) }
            .max { $0.probs[labelIndex] < $1.probs[labelIndex] }
    }
}
