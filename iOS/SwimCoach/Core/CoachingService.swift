import Foundation
import FoundationModels

struct CoachingService {

    static func generateTips(for result: AnalysisResult) async -> [String] {
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                return fallbackTips(for: result)
            }
            return await generateOnDevice(for: result)
        }
        return fallbackTips(for: result)
    }

    // MARK: - On-device via Apple Intelligence (iOS 26+, free, no API key)

    @available(iOS 26.0, *)
    private static func generateOnDevice(for result: AnalysisResult) async -> [String] {
        let issueLines = result.issues.isEmpty
            ? "No technique issues detected."
            : result.issues.map { "• \($0.displayName) (\($0.severity.rawValue)): \($0.description)" }
                .joined(separator: "\n")

        let prompt = """
        Swimmer analysis:
        - Score: \(result.score)/100 (Grade \(result.grade))
        - Strokes: \(result.strokeCount), Kick rate: \(Int(result.kickRatePerMin))/min
        - Asymmetry: \(Int(result.strokeAsymmetry * 100))%

        Issues:
        \(issueLines)

        Give exactly 3 short coaching tips (1–2 sentences each, specific and actionable). \
        Return only the tips, one per line, no numbering.
        """

        do {
            let session = LanguageModelSession(
                instructions: "You are a concise expert swim coach. Respond only with the requested tips."
            )
            let response = try await session.respond(to: prompt)
            let tips = response.content
                .components(separatedBy: "\n")
                .map { line -> String in
                    var s = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Strip markdown bold/italic markers
                    s = s.replacingOccurrences(of: "**", with: "")
                    s = s.replacingOccurrences(of: "__", with: "")
                    // Strip leading list markers (1. / - / • / *)
                    if let range = s.range(of: #"^[\d]+\.\s*"#, options: .regularExpression) { s.removeSubrange(range) }
                    if let range = s.range(of: #"^[-•*]\s+"#, options: .regularExpression) { s.removeSubrange(range) }
                    return s.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .filter { !$0.isEmpty }
            return Array(tips.prefix(3)).isEmpty ? fallbackTips(for: result) : Array(tips.prefix(3))
        } catch {
            return fallbackTips(for: result)
        }
    }

    // MARK: - Fallback (no model available)

    static func fallbackTips(for result: AnalysisResult) -> [String] {
        if result.issues.isEmpty {
            return [
                "Great session — your technique is solid. Focus on maintaining this consistency at higher intensities.",
                "Try descending sets (400→200→100) to practice holding good form as fatigue builds.",
                "Film yourself from the side every few weeks to track improvements over time."
            ]
        }
        return result.issues.prefix(3).map { $0.tip }
    }
}
