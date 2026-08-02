import Foundation

struct AnalysisResult: Hashable, Codable, Sendable {
    let id: UUID
    let score: Int
    let grade: String
    let strokeCount: Int
    let kickRatePerMin: Double
    let strokeAsymmetry: Double
    let frameCount: Int
    let sampledFrames: Int
    let fps: Double
    let issues: [TechniqueIssue]
    let tips: [String]
    let analyzedAt: Date
    /// File name of the analyzed video in SessionVideoStore (or a bundled
    /// resource name for demo sessions). Optional — sessions saved before
    /// video playback existed have none.
    var videoFileName: String? = nil
    /// Sampled pose keypoints for skeleton playback overlay. Optional —
    /// older sessions and demo sessions have none.
    var keypointFrames: [KeypointFrame]? = nil
    /// Per-window model probabilities with time spans (issue timeline /
    /// "see it" seeking). Optional — older sessions have none.
    var issueWindows: [IssueWindow]? = nil

    var detectionRate: Double {
        sampledFrames > 0 ? Double(frameCount) / Double(sampledFrames) : 1.0
    }

    /// Playable URL for this session's video, if it still exists.
    var videoURL: URL? {
        SessionVideoStore.url(forFileName: videoFileName)
    }

    var summary: String {
        if issues.isEmpty { return "Excellent technique — no issues detected." }
        let major = issues.filter { $0.severity == .major }.count
        let moderate = issues.filter { $0.severity == .moderate }.count
        if major > 0 { return "\(major) major issue\(major > 1 ? "s" : "") to address." }
        if moderate > 0 { return "\(moderate) technique issue\(moderate > 1 ? "s" : "") to work on." }
        return "\(issues.count) minor adjustment\(issues.count > 1 ? "s" : "") identified."
    }

    #if DEBUG
    static let demo = AnalysisResult(
        id: UUID(),
        score: 72,
        grade: "C",
        strokeCount: 48,
        kickRatePerMin: 52.0,
        strokeAsymmetry: 0.18,
        frameCount: 540,
        sampledFrames: 0,
        fps: 30.0,
        issues: [
            TechniqueIssue(
                name: "body_sag",
                displayName: "Body Sag",
                severity: .major,
                observedValue: 0.91,
                threshold: 0.45,
                description: "Hips and legs sinking below the waterline — creates significant drag.",
                tip: "Press your chest gently down to float your hips. Engage core every stroke."
            ),
            TechniqueIssue(
                name: "left_elbow_collapse",
                displayName: "Left Elbow Collapse",
                severity: .moderate,
                observedValue: 0.63,
                threshold: 0.45,
                description: "Left elbow dropping during the pull, losing your propulsive paddle.",
                tip: "High-elbow catch: point your elbow at the lane rope, not the pool floor."
            ),
            TechniqueIssue(
                name: "low_kick_rate",
                displayName: "Low Kick Rate",
                severity: .minor,
                observedValue: 0.52,
                threshold: 0.45,
                description: "Kick rate too low — hurts body rotation timing and forward balance.",
                tip: "Add a 2-beat kick (one per arm stroke) to keep your hips rotating."
            ),
        ],
        tips: [
            "Press your chest gently down to float your hips. Engage core every stroke.",
            "High-elbow catch: point your elbow at the lane rope, not the pool floor.",
            "Add a 2-beat kick (one per arm stroke) to keep your hips rotating.",
        ],
        analyzedAt: Date(),
        videoFileName: "swim_test.mp4",
        issueWindows: [
            IssueWindow(start: 0.0, end: 3.0,
                        probs: [0.2, 0.1, 0.3, 0.1, 0.1, 0.1, 0.55, 0.2, 0.35, 0.1]),
            IssueWindow(start: 1.5, end: 4.5,
                        probs: [0.2, 0.1, 0.6, 0.1, 0.1, 0.1, 0.85, 0.2, 0.50, 0.1]),
            IssueWindow(start: 3.0, end: 6.0,
                        probs: [0.2, 0.1, 0.7, 0.1, 0.1, 0.1, 0.95, 0.2, 0.60, 0.1]),
            IssueWindow(start: 4.5, end: 7.5,
                        probs: [0.2, 0.1, 0.5, 0.1, 0.1, 0.1, 0.90, 0.2, 0.55, 0.1]),
        ]
    )
    #endif
}

// MARK: - Codable (manual to handle missing sampledFrames in older stored sessions)

extension AnalysisResult {

    enum CodingKeys: String, CodingKey {
        case id, score, grade, strokeCount, kickRatePerMin, strokeAsymmetry
        case frameCount, sampledFrames, fps, issues, tips, analyzedAt
        case videoFileName, keypointFrames, issueWindows
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        score = try c.decode(Int.self, forKey: .score)
        grade = try c.decode(String.self, forKey: .grade)
        strokeCount = try c.decode(Int.self, forKey: .strokeCount)
        kickRatePerMin = try c.decode(Double.self, forKey: .kickRatePerMin)
        strokeAsymmetry = try c.decode(Double.self, forKey: .strokeAsymmetry)
        frameCount = try c.decode(Int.self, forKey: .frameCount)
        sampledFrames = try c.decodeIfPresent(Int.self, forKey: .sampledFrames) ?? 0
        fps = try c.decode(Double.self, forKey: .fps)
        issues = try c.decode([TechniqueIssue].self, forKey: .issues)
        tips = try c.decode([String].self, forKey: .tips)
        analyzedAt = try c.decode(Date.self, forKey: .analyzedAt)
        videoFileName = try c.decodeIfPresent(String.self, forKey: .videoFileName)
        keypointFrames = try c.decodeIfPresent([KeypointFrame].self, forKey: .keypointFrames)
        issueWindows = try c.decodeIfPresent([IssueWindow].self, forKey: .issueWindows)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(score, forKey: .score)
        try c.encode(grade, forKey: .grade)
        try c.encode(strokeCount, forKey: .strokeCount)
        try c.encode(kickRatePerMin, forKey: .kickRatePerMin)
        try c.encode(strokeAsymmetry, forKey: .strokeAsymmetry)
        try c.encode(frameCount, forKey: .frameCount)
        try c.encode(sampledFrames, forKey: .sampledFrames)
        try c.encode(fps, forKey: .fps)
        try c.encode(issues, forKey: .issues)
        try c.encode(tips, forKey: .tips)
        try c.encode(analyzedAt, forKey: .analyzedAt)
        try c.encodeIfPresent(videoFileName, forKey: .videoFileName)
        try c.encodeIfPresent(keypointFrames, forKey: .keypointFrames)
        try c.encodeIfPresent(issueWindows, forKey: .issueWindows)
    }
}
