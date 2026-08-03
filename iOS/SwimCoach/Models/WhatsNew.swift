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
        Highlight(icon: "moon.stars",
                  title: "Night Meet dark theme",
                  detail: "The app now follows system appearance — dark renders the meet sheet on an evening pool deck: chalk ink, chlorine-blue lane lines, severity colors retuned to hold contrast."),
        Highlight(icon: "timeline.selection",
                  title: "Tap an issue, see the moment",
                  detail: "The lane under the Results video now maps every detection by severity across the clip — tap a mark and the video jumps straight to that stroke."),
        Highlight(icon: "square.and.arrow.up",
                  title: "Shareable session card",
                  detail: "SHARE CARD in Results renders your session as a square social image — score, verdict, top issues — straight to the share sheet."),
        Highlight(icon: "tablecells",
                  title: "Your history as a spreadsheet",
                  detail: "About → Your data now exports a CSV — one row per session — alongside the JSON archive."),
    ]
}
