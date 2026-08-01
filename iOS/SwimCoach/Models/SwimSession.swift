import Foundation
import SwiftData

@Model
final class SwimSession {
    var id: UUID
    var name: String = ""
    var score: Int
    var grade: String
    var issueCount: Int
    var strokeCount: Int
    var kickRatePerMin: Double
    var analyzedAt: Date
    @Attribute(.externalStorage) var resultData: Data

    init(result: AnalysisResult) {
        self.id = result.id
        self.name = ""
        self.score = result.score
        self.grade = result.grade
        self.issueCount = result.issues.count
        self.strokeCount = result.strokeCount
        self.kickRatePerMin = result.kickRatePerMin
        self.analyzedAt = result.analyzedAt
        self.resultData = (try? JSONEncoder().encode(result)) ?? Data()
    }

    func decoded() -> AnalysisResult? {
        try? JSONDecoder().decode(AnalysisResult.self, from: resultData)
    }
}
