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
        Highlight(icon: "target",
                  title: "Weekly goals, per swimmer",
                  detail: "The goal follows the Home swimmer scope — each swimmer holds their own target, inheriting the Everyone goal until they set one."),
        Highlight(icon: "tablecells",
                  title: "Your history as a spreadsheet",
                  detail: "About → Your data now exports a CSV — one row per session — alongside the JSON archive."),
        Highlight(icon: "square.and.arrow.up",
                  title: "Shareable session card",
                  detail: "SHARE CARD in Results renders your session as a square social image — score, verdict, top issues — straight to the share sheet."),
    ]
}
