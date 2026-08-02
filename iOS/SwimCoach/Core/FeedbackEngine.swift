import Foundation

// Maps SwimTCN probability outputs (10-element vector) to TechniqueIssue objects.
// Label order must match ISSUE_LABELS in swim-analyzer/ml/model.py exactly.
struct FeedbackEngine {

    static let threshold: Float = 0.45

    private static let catalog: [(name: String, display: String,
                                   baseSev: TechniqueIssue.Severity,
                                   desc: String, tip: String)] = [
        ("left_elbow_overextension",  "Left Elbow Overextension",  .moderate,
         "Left arm entering water too rigidly — reduces reach and shoulder efficiency.",
         "On entry, imagine reaching over a barrel: arm nearly straight, wrist relaxed."),

        ("right_elbow_overextension", "Right Elbow Overextension", .moderate,
         "Right arm entering water too rigidly — reduces reach and shoulder efficiency.",
         "On entry, imagine reaching over a barrel: arm nearly straight, wrist relaxed."),

        ("left_elbow_collapse",       "Left Elbow Collapse",       .moderate,
         "Left elbow dropping during the pull, losing your propulsive paddle.",
         "High-elbow catch: point your elbow at the lane rope, not the pool floor."),

        ("right_elbow_collapse",      "Right Elbow Collapse",      .moderate,
         "Right elbow dropping during the pull, losing your propulsive paddle.",
         "High-elbow catch: point your elbow at the lane rope, not the pool floor."),

        ("left_knee_overbend",        "Left Knee Overbend",        .minor,
         "Left knee bending too much during kick — creating drag instead of thrust.",
         "Power comes from your hips. Keep legs loose but mostly straight."),

        ("right_knee_overbend",       "Right Knee Overbend",       .minor,
         "Right knee bending too much during kick — creating drag instead of thrust.",
         "Power comes from your hips. Keep legs loose but mostly straight."),

        ("body_sag",                  "Body Sag",                  .major,
         "Hips and legs sinking below the waterline — creates significant drag.",
         "Press your chest gently down to float your hips. Engage core every stroke."),

        ("stroke_asymmetry",          "Stroke Asymmetry",          .moderate,
         "Left-right stroke imbalance — causes lateral drift and reduces efficiency.",
         "Try catch-up drill: leading arm extends fully before the other side pulls."),

        ("low_kick_rate",             "Low Kick Rate",             .minor,
         "Kick rate too low — hurts body rotation timing and forward balance.",
         "Add a 2-beat kick (one per arm stroke) to keep your hips rotating."),

        ("excessive_kick_rate",       "Excessive Kick Rate",       .minor,
         "Kick rate too high — burning energy with diminishing propulsive return.",
         "Settle into a 6-beat kick for aerobic efforts, 2-beat for distance."),
    ]

    /// Index of a label in catalog/probability order (for issue timelines).
    static func labelIndex(of name: String) -> Int? {
        catalog.firstIndex { $0.name == name }
    }

    /// Every issue name the model can emit, in probability order.
    static var issueNames: [String] { catalog.map(\.name) }

    static func decode(probabilities: [Float]) -> [TechniqueIssue] {
        probabilities.enumerated().compactMap { i, prob in
            guard i < catalog.count, prob >= threshold else { return nil }
            let m = catalog[i]
            let sev: TechniqueIssue.Severity = prob > 0.8
                ? (m.baseSev == .minor ? .moderate : .major)
                : m.baseSev
            return TechniqueIssue(
                name: m.name,
                displayName: m.display,
                severity: sev,
                observedValue: Double(prob),
                threshold: Double(threshold),
                description: m.desc,
                tip: m.tip
            )
        }
    }
}
