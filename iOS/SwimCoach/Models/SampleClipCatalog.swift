import Foundation

/// The bundled sample swims — somebody else's footage, shipped so a swimmer
/// who has not filmed anything yet can still watch the app work.
///
/// ── What a row is allowed to say ────────────────────────────────────────
///
/// Every field here describes the FOOTAGE: where the camera was, what is in
/// frame. None of them describes a finding. That is deliberate and it is the
/// same rule `VerdictChip` states from the other side — anything the app did
/// not measure must not wear the mark of something it did. Pre-printing "Left
/// Elbow Collapse (moderate)" next to a clip would be exactly that: a verdict
/// stated before this iPhone has run a single frame through SwimTCN, and one
/// that could disagree with what the run actually produces. The findings
/// belong on the Results screen, after the model has earned them.
///
/// ── Adding a fifth clip ─────────────────────────────────────────────────
///
/// Drop the file into `Resources/SampleClips/` and add one entry to `all`.
/// Nothing else: the list screen, the bundle-resolution test and the
/// no-save rule in `AnalyzingView` all read this catalog rather than
/// enumerating clips of their own.
struct SampleClip: Identifiable, Hashable, Sendable {
    /// Bundle resource name, extension included. Doubles as the identity —
    /// two rows cannot name the same file without colliding here first.
    let fileName: String
    /// Row title, in the app's voice.
    let title: String
    /// Where the camera was, for the data register. All caps at the call site.
    let vantage: String
    /// One sentence on what the clip actually shows.
    let footage: String

    var id: String { fileName }

    var resourceName: String { (fileName as NSString).deletingPathExtension }
    var resourceExtension: String { (fileName as NSString).pathExtension }

    /// Where the clip is in the built product, or nil when it did not ship.
    ///
    /// Resolved through `Bundle.main.url(forResource:withExtension:)` rather
    /// than by building a path, because that is the same call
    /// `SessionVideoStore.persist` uses to recognise a bundled source — so
    /// the URL this hands to analysis is *identical* to the one persist
    /// tests against, and a sample is never copied into the session store.
    func bundleURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: resourceName, withExtension: resourceExtension)
    }
}

/// The credit the licence obliges the app to show. Held as fields rather than
/// one baked string so the screen can typeset the parts (author in ink, the
/// licence as a link) without re-splitting prose.
struct SampleClipAttribution: Hashable, Sendable {
    let work: String
    let author: String
    let source: String
    /// Spelled out, the way About names the SIL OFL.
    let licenseName: String
    /// The short form, for the register line.
    let licenseShortName: String
    let licenseURL: URL

    /// The one sentence that carries every element CC BY 3.0 §4(c) asks for:
    /// the title of the work, the author's name, and the licence.
    var creditLine: String {
        "\"\(work)\" by \(author), via \(source), used under the \(licenseName) licence."
    }
}

enum SampleClipCatalog {

    /// All four clips come from one work, so this is a property of the
    /// catalog rather than of each row.
    static let attribution = SampleClipAttribution(
        work: "Mary's Swim Boot Camp",
        author: "koolkatkari",
        source: "Wikimedia Commons",
        licenseName: "Creative Commons Attribution 3.0",
        licenseShortName: "CC BY 3.0",
        // Force-unwrap on a compile-time constant that is either valid
        // forever or caught by `SampleClipCatalogTests` on the first run.
        licenseURL: URL(string: "https://creativecommons.org/licenses/by/3.0")!)

    static let all: [SampleClip] = [
        SampleClip(
            fileName: "sample_poolside.mp4",
            title: "Deck level, side on",
            vantage: "Above water",
            footage: "Filmed from the pool deck with the camera down at the waterline, panning with the swimmer — the framing SwimCoach asks you for."),
        SampleClip(
            fileName: "sample_underwater_a.mp4",
            title: "Underwater, close pass",
            vantage: "Underwater",
            footage: "Side on from under the surface, held against the lane rope as the swimmer goes by within arm's reach."),
        SampleClip(
            fileName: "sample_underwater_b.mp4",
            title: "Underwater, whole length",
            vantage: "Underwater",
            footage: "Side on from under the surface, picking the swimmer up at distance and holding them all the way past the camera."),
        SampleClip(
            fileName: "sample_underwater_c.mp4",
            title: "Underwater, down the lane",
            vantage: "Underwater",
            footage: "From under the surface looking along the lane — the swimmer comes head on toward the camera and passes it."),
    ]

    /// The sample this URL *is*, or nil for footage the user supplied.
    ///
    /// This is the whole seam between a sample run and a real one. It is an
    /// identity check against the bundle, never a filename match, for the
    /// same reason `AnalyzingView` already checks the demo clip that way: a
    /// swim the user filmed and a swim we shipped must not become
    /// interchangeable because they happen to share a name. A user file
    /// called `sample_poolside.mp4` lives in the session store or the photo
    /// library, resolves to a different URL, and gets the full treatment —
    /// real analysis, saved to history.
    ///
    /// A clip that failed to ship resolves to nil and therefore matches
    /// nothing, which fails safe: the row cannot be tapped in the first
    /// place (`SampleSwimsView` disables it), and nothing can be
    /// misclassified as a sample.
    static func sample(for url: URL, in bundle: Bundle = .main) -> SampleClip? {
        all.first { $0.bundleURL(in: bundle) == url }
    }

    /// True when analysis must NOT write a `SwimSession` for this footage.
    ///
    /// Named for the decision rather than for the check, so the call site in
    /// `AnalyzingView` reads as the policy it is enforcing.
    static func isSample(_ url: URL, in bundle: Bundle = .main) -> Bool {
        sample(for: url, in: bundle) != nil
    }
}
