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

    /// The one sentence that carries every element CC BY-SA 4.0 §3(a)(1) asks
    /// for: the title of the work, the author's name, the licence — and,
    /// because ShareAlike obliges it, an indication that the material was
    /// modified. Every clip here was trimmed and rescaled to ship, so that
    /// last clause is not optional boilerplate.
    var creditLine: String {
        "\"\(work)\" by \(author), via \(source), used under the "
            + "\(licenseName) licence. Trimmed and rescaled for this app."
    }
}

enum SampleClipCatalog {

    /// All three clips are one author's, under one licence, so this is a
    /// property of the catalog rather than of each row.
    static let attribution = SampleClipAttribution(
        work: "Front Crawl Above Water, Front Crawl Underwater and Sprint Front Crawl Underwater",
        author: "It is a wonderful world",
        source: "Wikimedia Commons",
        licenseName: "Creative Commons Attribution-ShareAlike 4.0",
        licenseShortName: "CC BY-SA 4.0",
        // Force-unwrap on a compile-time constant that is either valid
        // forever or caught by `SampleClipCatalogTests` on the first run.
        licenseURL: URL(string: "https://creativecommons.org/licenses/by-sa/4.0")!)

    /// ── Why these three, and why front crawl only ───────────────────────
    ///
    /// Two filters decided this list, and the first one is not obvious.
    ///
    /// **Vision has to be able to see the swimmer.** The app's gate needs ten
    /// usable observations (`AnalyzingView`), where usable means a body that
    /// is horizontal-or-unknown AND of plausible torso size
    /// (`PoseAnalyzer.minTorsoLength`, 0.09 of frame height). An earlier set
    /// of clips passed MediaPipe in `ml/` and scored 0, 0, 3 and 1 here —
    /// every one rejected on device — because the swimmer sat 0.05–0.06 of
    /// the frame and Vision fitted a near-vertical body to them. MediaPipe
    /// tolerates a distant swimmer; Vision does not. **Probe a candidate
    /// through Vision before adding it, not through the Python pipeline** —
    /// the Python gate is a mirror of the thresholds, not of the detector.
    /// These three measure a 0.11–0.18 median torso and 14, 18 and 41 usable
    /// observations respectively.
    ///
    /// **The model only knows freestyle.** `FeedbackEngine.catalog` is ten
    /// front-crawl faults — elbow collapse, knee overbend, kick rate, body
    /// sag, asymmetry. Breaststroke and butterfly footage from the same
    /// source passes the gate perfectly well and would produce confident,
    /// meaningless output: freestyle faults scored against a stroke that
    /// never claimed to have them.
    static let all: [SampleClip] = [
        SampleClip(
            fileName: "sample_crawl_deck.mp4",
            title: "Deck level, side on",
            vantage: "Above water",
            footage: "Filmed from the pool deck with the camera down at the waterline, tracking the swimmer past — the framing SwimCoach asks you for."),
        SampleClip(
            fileName: "sample_crawl_underwater.mp4",
            title: "Underwater, side on",
            vantage: "Underwater",
            footage: "Side on from under the surface, holding the swimmer in frame for several full stroke cycles."),
        SampleClip(
            fileName: "sample_crawl_sprint.mp4",
            title: "Underwater, sprint tempo",
            vantage: "Underwater",
            footage: "The same vantage at racing turnover, where the stroke is faster and the catch is harder to hold."),
    ]

    /// The sample this URL *is*, or nil for footage the user supplied.
    ///
    /// This is the whole seam between a sample run and a real one. It is an
    /// identity check against the bundle, never a filename match, for the
    /// same reason `AnalyzingView` already checks the demo clip that way: a
    /// swim the user filmed and a swim we shipped must not become
    /// interchangeable because they happen to share a name. A user file
    /// called `sample_crawl_deck.mp4` lives in the session store or the photo
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
