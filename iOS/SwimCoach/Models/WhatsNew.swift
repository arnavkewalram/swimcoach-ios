import Foundation

/// Release highlights surfaced once per version — updates should
/// announce themselves instead of hiding behind data-gated panels.
enum WhatsNew {

    struct Highlight: Identifiable, Equatable {
        let icon: String
        let title: String
        let detail: String
        var id: String { title }
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Show when the user has seen SOME earlier version (fresh installs
    /// get onboarding instead) and this version is different. Pure.
    static func shouldShow(current: String, lastSeen: String) -> Bool {
        !lastSeen.isEmpty && lastSeen != current
    }

    /// Highlights for the current release wave. Curated, not exhaustive —
    /// update alongside CHANGELOG when headline features ship.
    static let highlights: [Highlight] = [
        Highlight(icon: "photo.on.rectangle",
                  title: "Import from Photos",
                  detail: "Analyze any swim video from your library — not just live recordings."),
        Highlight(icon: "figure.pool.swim",
                  title: "Drill library",
                  detail: "Ten drills mapped to every fault the analysis can detect, linked from your results."),
        Highlight(icon: "chart.line.uptrend.xyaxis",
                  title: "Training log, goals & focus",
                  detail: "Home tracks your score trend, weekly goal, and the fault most worth working on."),
        Highlight(icon: "square.and.arrow.up",
                  title: "Share the proof",
                  detail: "Export your video with the skeleton burned in, or a report card with your progress curve."),
        Highlight(icon: "metronome",
                  title: "Stroke rate & trends",
                  detail: "Strokes per minute on every new analysis; History shows 12-week consistency and per-fault direction."),
    ]
}
