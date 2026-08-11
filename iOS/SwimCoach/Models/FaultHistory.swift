import Foundation

/// One fault, read across the whole swim library — the numbers behind that
/// fault's own page.
///
/// Pure over plain values so the rule is unit-testable without SwiftData,
/// and deliberately thin: almost nothing here is a new statistic. Presence
/// direction is `IssueTrend`'s, so the arrow on the fault page is the same
/// arrow History's COMMON ISSUES bar already showed. The recent window is
/// `FocusFault.window`, so the sentence agrees with the Focus panel that
/// may have sent the swimmer here. The identity scope is `DrillEffect`'s.
/// The one genuinely new series is detection strength, which no other
/// surface reads across sessions.
///
/// ── Scope: one rule, applied once ───────────────────────────────────────
///
/// `DrillEffect.resolvedScope` picks whose history this is, and
/// `DrillEffect.belongs` filters the swims — both inside `summary`, before
/// anything is counted, so a caller cannot scope the boundary and leave a
/// statistic unscoped. Every number the page shows (first seen, the recent
/// window, the strength series, the session list, and the drill read-outs
/// it hands to `DrillEffect`) descends from that single filtered set.
/// An empty scope means everyone; a name the library no longer knows falls
/// back to everyone rather than blanking the page. See `DrillEffect`'s
/// header for why that is the rule and not a second one.
///
/// ── Detection strength ──────────────────────────────────────────────────
///
/// `TechniqueIssue.observedValue` is the model's confidence in this fault
/// for one swim, and it lives only inside the stored result blob. Callers
/// open that blob for the swims that need it and pass what they read; a
/// swim known to contain the fault whose blob would NOT read still counts
/// toward frequency and simply plots no point. Reading it as fault-free
/// would manufacture an improvement out of a storage detail — the same rule
/// `DrillEffect.isLegacyRow` states for presence.
enum FaultHistory {

    /// Appearances needed before a strength move is claimed — two per half,
    /// so a single loud or quiet swim can never produce one.
    static let minStrengthSamples = 4

    /// Mean-confidence change that counts as movement. The same floor
    /// `SessionComparison` uses between two swims: below it, a probability
    /// difference is model noise rather than progress.
    static let strengthThreshold = SessionComparison.changeThreshold

    // MARK: - Input

    /// One analyzed swim, reduced to what the fault page reads.
    struct Swim: Equatable {
        let id: UUID
        let date: Date
        /// Session name; empty when the swimmer never set one.
        let name: String
        let score: Int
        let grade: String
        /// Empty means untagged, matching `SwimSession.swimmer`.
        let swimmer: String
        /// Every fault detected in this swim.
        let faults: [String]
        /// Model confidence per fault, for the swims whose stored result
        /// could be read. A fault listed in `faults` with no entry here
        /// counts toward frequency but plots no strength point.
        let strengths: [String: Double]

        init(id: UUID = UUID(),
             date: Date,
             name: String = "",
             score: Int = 0,
             grade: String = "",
             swimmer: String = "",
             faults: [String],
             strengths: [String: Double] = [:]) {
            self.id = id
            self.date = date
            self.name = name
            self.score = score
            self.grade = grade
            self.swimmer = swimmer
            self.faults = faults
            self.strengths = strengths
        }
    }

    // MARK: - Output

    /// A swim where the fault was detected.
    struct Appearance: Equatable, Identifiable {
        /// The session's id — how the page routes back to its Results.
        let id: UUID
        let date: Date
        let name: String
        let score: Int
        let grade: String
        /// Model confidence, 0–1. `nil` when this swim's stored result
        /// would not decode: the appearance is real, the number is not
        /// known, and the strength line breaks rather than inventing one.
        let strength: Double?
        /// 1-based position in the scoped chronological library — the same
        /// integer X axis History's score trend plots on.
        let swimIndex: Int
        /// Contiguity run over PLOTTABLE appearances, so the strength line
        /// breaks across a reading it could not take instead of drawing
        /// through it. Meaningless where `strength` is nil. Mirrors
        /// `MetricTrend.Point.run`.
        let run: Int

        /// Could the app read this swim's stored result?
        ///
        /// The same fact `strength != nil` carries — a confidence is only
        /// ever missing from an appearance because the blob it lives in
        /// would not decode — named so that a caller asking the STORAGE
        /// question does not have to infer it from a number's absence. The
        /// fault page asks it to decide whether a row may offer a tap
        /// through to results that cannot be opened.
        var resultIsReadable: Bool { strength != nil }
    }

    /// Which way the model's confidence has moved: recent half of the
    /// appearances against the earlier half, the same split `IssueTrend`
    /// uses on presence.
    enum StrengthMove: Equatable {
        case easing      // the model is less sure than it was
        case building    // more sure
        case steady
    }

    struct StrengthShift: Equatable {
        let move: StrengthMove
        let earlierMean: Double
        let recentMean: Double

        var delta: Double { recentMean - earlierMean }
    }

    /// Everything the fault page claims, derived in one pass.
    struct Summary: Equatable {
        let fault: String
        /// Scoped swims considered — the denominator of every claim here.
        let totalSwims: Int
        /// Swims containing the fault, chronological, oldest first.
        let appearances: [Appearance]
        /// Appearances inside the trailing `recentWindow` swims.
        let recentCount: Int
        /// `FocusFault.window`, or the whole library when it is shorter.
        let recentWindow: Int
        /// Presence direction across the full history, by `IssueTrend`.
        let trend: IssueTrend
        /// nil until `minStrengthSamples` readable appearances exist.
        let strength: StrengthShift?
        /// Swims analyzed since the fault last appeared — 0 when it was in
        /// the most recent swim, nil when it has never appeared.
        let swimsSinceLastSeen: Int?

        var isSeen: Bool { !appearances.isEmpty }
        var seenCount: Int { appearances.count }
        var firstSeen: Appearance? { appearances.first }
        var lastSeen: Appearance? { appearances.last }
        /// Appearances with a confidence reading — what the chart draws.
        var plottable: [Appearance] { appearances.filter { $0.strength != nil } }
        /// A line needs two points; one reading is a dot, not a trend.
        var isStrengthPlottable: Bool { plottable.count >= 2 }
    }

    // MARK: - What has to be read off disk

    /// Does answering for `fault` require opening this session's stored
    /// result blob?
    ///
    /// The page's whole performance contract, as a rule rather than a
    /// comment. `observedValue` lives only inside the externally-stored
    /// blob, so reading it costs a disk read plus a JSON pass over the
    /// session's keypoint frames — the exact cost v1.43.4 and v1.45.5 were
    /// both shipped to stop paying. Two kinds of session need one:
    ///
    ///   • one whose stored `issueNames` column names this fault, because
    ///     its confidence is the series this page plots;
    ///   • a legacy row, whose column migrated in empty and which therefore
    ///     has no other record of what it contained.
    ///
    /// Every other swim is answered from columns. A library of a hundred
    /// swims that never had this fault costs zero decodes, which is what the
    /// test on this function pins.
    static func needsResultBlob(issueNames: [String],
                                issueCount: Int,
                                fault: String) -> Bool {
        DrillEffect.isLegacyRow(issueNames: issueNames, issueCount: issueCount)
            || issueNames.contains(fault)
    }

    // MARK: - The pass

    /// The fault page's whole read-out.
    ///
    /// - Parameters:
    ///   - fault: the `FeedbackEngine` issue name being examined.
    ///   - swims: every stored swim, ANY order, passed UNFILTERED — the
    ///     scope is applied here so the boundary and the statistics cannot
    ///     drift apart. Callers must DROP legacy rows they cannot resolve
    ///     rather than pass them in fault-free (see `DrillEffect`).
    ///   - activeSwimmer: identity scope; "" means everyone.
    static func summary(of fault: String,
                        in swims: [Swim],
                        activeSwimmer: String = "") -> Summary {
        let scope = DrillEffect.resolvedScope(activeSwimmer,
                                              knownSwimmers: swims.map(\.swimmer))
        let scoped = swims
            .filter { DrillEffect.belongs($0.swimmer, to: scope) }
            .sorted { $0.date < $1.date }

        let presence = scoped.map { $0.faults.contains(fault) }
        let appearances = appearances(of: fault, in: scoped)
        let window = min(FocusFault.window, scoped.count)

        return Summary(
            fault: fault,
            totalSwims: scoped.count,
            appearances: appearances,
            recentCount: presence.suffix(window).filter { $0 }.count,
            recentWindow: window,
            trend: IssueTrend.trend(occurrences: presence),
            strength: shift(across: appearances.compactMap(\.strength)),
            swimsSinceLastSeen: appearances.last.map { scoped.count - $0.swimIndex })
    }

    /// Chronological swims → the ones containing `fault`, tagged with their
    /// position in the library and their contiguity run.
    private static func appearances(of fault: String,
                                    in scoped: [Swim]) -> [Appearance] {
        var result: [Appearance] = []
        var run = 0
        var lastPlottedOrdinal: Int? = nil
        for (offset, swim) in scoped.enumerated() where swim.faults.contains(fault) {
            let strength = swim.strengths[fault]
            if strength != nil {
                if let last = lastPlottedOrdinal, last != result.count - 1 { run += 1 }
                lastPlottedOrdinal = result.count
            }
            result.append(Appearance(id: swim.id, date: swim.date, name: swim.name,
                                     score: swim.score, grade: swim.grade,
                                     strength: strength, swimIndex: offset + 1,
                                     run: run))
        }
        return result
    }

    /// Recent half of the readings against the earlier half. Same split as
    /// `IssueTrend`: with an odd count the extra reading goes to the
    /// earlier side, so the recent half is never padded with old data.
    private static func shift(across strengths: [Double]) -> StrengthShift? {
        guard strengths.count >= minStrengthSamples else { return nil }
        let half = strengths.count / 2
        let earlier = strengths.prefix(strengths.count - half)
        let recent = strengths.suffix(half)
        let earlierMean = earlier.reduce(0, +) / Double(earlier.count)
        let recentMean = recent.reduce(0, +) / Double(recent.count)
        let delta = recentMean - earlierMean
        let move: StrengthMove = delta <= -strengthThreshold ? .easing
            : delta >= strengthThreshold ? .building : .steady
        return StrengthShift(move: move, earlierMean: earlierMean, recentMean: recentMean)
    }
}

// MARK: - Copy
//
// Beside the rule, like `DrillEffect`'s, so the wording is unit-testable and
// no view can quietly upgrade a count into a claim. Nothing here says a
// fault was caused or cured by anything; the strongest phrasing available
// is "showing up less often".

extension FaultHistory.Summary {

    /// "In 3 of your last 5 swims." — the sentence Home's Focus panel
    /// makes, over the same window, so a swimmer arriving from there is not
    /// shown two different versions of the same fact.
    var recentLine: String {
        "In \(recentCount) of your last \(DrillEffect.swimCount(recentWindow))."
    }

    /// What to say instead of a page, when there is nothing to plot — nil
    /// once there is.
    ///
    /// One optional carrying BOTH lines, rather than a headline and a detail
    /// that happen to appear and disappear together: the view renders this
    /// or the cards, and a pair that could go half-nil is a page that could
    /// render blank.
    var empty: (headline: String, detail: String)? {
        if totalSwims == 0 {
            return ("No swims analyzed yet",
                    "Analyze a swim and this page fills in with every time the model finds it.")
        }
        if !isSeen {
            return ("Not seen in your swims",
                    "The model hasn't flagged this in any of your \(DrillEffect.swimCount(totalSwims)).")
        }
        return nil
    }

    /// "In every swim since." / "Not in your last 4 swims." — where the
    /// fault stands right now, which a count alone does not say.
    var standingLine: String? {
        guard let since = swimsSinceLastSeen else { return nil }
        if since == 0 { return "Found in your most recent swim." }
        return "Not in your last \(DrillEffect.swimCount(since))."
    }
}

// The wording for the presence trend itself is NOT here. `IssueTrend.flat`
// means two different things — measured and level, or too short a library to
// look — and a lone `trendLabel` string could only render them alike. That
// choice lives in `FaultDetailPresentation`, which returns a different SHAPE for each.

extension FaultHistory.StrengthShift {
    var headline: String {
        switch move {
        case .easing:   return "EASING"
        case .building: return "BUILDING"
        case .steady:   return "STEADY"
        }
    }

    /// The two means the verdict came from, as the percentages the rest of
    /// the app shows confidences in.
    var detail: String {
        "Averaged \(FaultHistory.percent(earlierMean)) early, "
            + "\(FaultHistory.percent(recentMean)) lately."
    }
}

extension FaultHistory {
    /// A model probability as the whole percent the app displays.
    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
