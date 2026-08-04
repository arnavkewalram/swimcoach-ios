import Foundation
import SwiftData

@Model
final class SwimSession {
    var id: UUID
    var name: String = ""
    /// Free-text training note ("worked on catch", "felt heavy").
    /// Defaulted so existing stores migrate losslessly.
    var notes: String = ""
    /// Who swam — lets one phone track multiple swimmers. Defaulted for
    /// lossless migration; empty means untagged.
    var swimmer: String = ""
    var score: Int
    var grade: String
    var issueCount: Int
    /// Fault names for cheap Home-screen aggregation (no blob decode).
    /// Defaulted so existing stores migrate; old sessions stay empty.
    var issueNames: [String] = []
    var strokeCount: Int
    var kickRatePerMin: Double
    /// Analyzed clip length in seconds, stored so History can derive stroke
    /// rate (strokeCount / minutes) without decoding the result blob per row.
    /// Defaulted so existing stores migrate losslessly; 0 means unknown
    /// (sessions saved before this field) and renders as a gap in trends.
    var durationSeconds: Double = 0
    var analyzedAt: Date
    @Attribute(.externalStorage) var resultData: Data

    init(result: AnalysisResult) {
        self.id = result.id
        self.name = ""
        self.score = result.score
        self.grade = result.grade
        self.issueCount = result.issues.count
        self.issueNames = result.issues.map(\.name)
        self.strokeCount = result.strokeCount
        self.kickRatePerMin = result.kickRatePerMin
        self.durationSeconds = result.durationSeconds ?? 0
        self.analyzedAt = result.analyzedAt
        self.resultData = (try? JSONEncoder().encode(result)) ?? Data()
    }

    func decoded() -> AnalysisResult? {
        try? JSONDecoder().decode(AnalysisResult.self, from: resultData)
    }
}
