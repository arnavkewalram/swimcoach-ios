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
    /// Analyzed clip duration. Optional — sessions saved before stroke
    /// rate existed have none.
    var durationSeconds: Double? = nil

    /// Strokes per minute — the tempo number coaches use.
    var strokeRatePerMin: Double? {
        guard let d = durationSeconds, d > 0 else { return nil }
        return Double(strokeCount) / d * 60.0
    }

    /// "M:SS" clip length for display, nil for legacy sessions.
    var durationText: String? {
        guard let d = durationSeconds, d > 0 else { return nil }
        let total = Int(d.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

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
        keypointFrames: demoKeypointFrames,
        issueWindows: [
            IssueWindow(start: 0.0, end: 3.0,
                        probs: [0.2, 0.1, 0.3, 0.1, 0.1, 0.1, 0.55, 0.2, 0.35, 0.1]),
            IssueWindow(start: 1.5, end: 4.5,
                        probs: [0.2, 0.1, 0.6, 0.1, 0.1, 0.1, 0.85, 0.2, 0.50, 0.1]),
            IssueWindow(start: 3.0, end: 6.0,
                        probs: [0.2, 0.1, 0.7, 0.1, 0.1, 0.1, 0.95, 0.2, 0.60, 0.1]),
            IssueWindow(start: 4.5, end: 7.5,
                        probs: [0.2, 0.1, 0.5, 0.1, 0.1, 0.1, 0.90, 0.2, 0.55, 0.1]),
        ],
        durationSeconds: 60
    )

    /// Synthetic skeleton path matching the demo cartoon's swimmer band —
    /// makes the overlay and export demo-able without a real analysis.
    static let demoKeypointFrames: [KeypointFrame] = (0..<27).map { i in
        let t = Double(i) * 0.3
        let x = Float(0.10 + Double(i) * 0.008)
        let y: Float = 0.50
        var joints = [Float](repeating: 0, count: 39)
        // Rough horizontal swimmer: head at +0.10x, feet at -0.10x from center
        let layout: [(Float, Float)] = [
            (0.10, 0.00),                     // nose
            (0.05, -0.015), (0.05, 0.015),    // shoulders
            (0.02, -0.030), (0.02, 0.030),    // elbows
            (-0.01, -0.045), (-0.01, 0.045),  // wrists
            (-0.03, -0.012), (-0.03, 0.012),  // hips
            (-0.06, -0.015), (-0.06, 0.015),  // knees
            (-0.10, -0.018), (-0.10, 0.018),  // ankles
        ]
        for (j, off) in layout.enumerated() {
            joints[j * 3]     = x + off.0
            joints[j * 3 + 1] = y + off.1
            joints[j * 3 + 2] = 0.9
        }
        return KeypointFrame(t: t, joints: joints)
    }

    /// An earlier, weaker session for the compare demo: body_sag worse then,
    /// late_hand_entry has since resolved, low_kick_rate unchanged, and
    /// left_elbow_collapse is NEW in the later session.
    static let demoEarlier = AnalysisResult(
        id: UUID(),
        score: 61,
        grade: "D",
        strokeCount: 44,
        kickRatePerMin: 38.0,
        strokeAsymmetry: 0.26,
        frameCount: 500,
        sampledFrames: 0,
        fps: 30.0,
        issues: [
            TechniqueIssue(
                name: "body_sag",
                displayName: "Body Sag",
                severity: .major,
                observedValue: 0.97,
                threshold: 0.45,
                description: "Hips and legs sinking below the waterline — creates significant drag.",
                tip: "Press your chest gently down to float your hips. Engage core every stroke."
            ),
            TechniqueIssue(
                name: "late_hand_entry",
                displayName: "Late Hand Entry",
                severity: .moderate,
                observedValue: 0.58,
                threshold: 0.45,
                description: "Hand entering the water past the head centerline.",
                tip: "Reach straight forward from the shoulder."
            ),
            TechniqueIssue(
                name: "low_kick_rate",
                displayName: "Low Kick Rate",
                severity: .minor,
                observedValue: 0.50,
                threshold: 0.45,
                description: "Kick rate too low — hurts body rotation timing and forward balance.",
                tip: "Add a 2-beat kick (one per arm stroke) to keep your hips rotating."
            ),
        ],
        tips: [],
        analyzedAt: Date().addingTimeInterval(-7 * 24 * 3600)
    )
    #endif
}

// MARK: - Codable (manual to handle missing sampledFrames in older stored sessions)

extension AnalysisResult {

    enum CodingKeys: String, CodingKey {
        case id, score, grade, strokeCount, kickRatePerMin, strokeAsymmetry
        case frameCount, sampledFrames, fps, issues, tips, analyzedAt
        case videoFileName, keypointFrames, issueWindows, durationSeconds
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
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds)
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
        try c.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
    }
}
