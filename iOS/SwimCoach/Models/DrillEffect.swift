import Foundation

/// "Is this drill working?" — the read-out that closes the loop between a
/// drill's MARK DONE taps and the faults the analysis keeps finding.
///
/// Pure over plain values (practice dates, dated fault lists, the drill's
/// `fixes`) so the whole rule is unit-testable without SwiftData.
///
/// ── The rule, and why it is this one ────────────────────────────────────
///
/// **Boundary — the first practice tap.** A drill's `before` set is the
/// swims analyzed strictly before the swimmer's *earliest* tap on it;
/// `after` is everything from that instant on. The first tap is the only
/// event in the data that means "started", which is exactly the claim the
/// copy makes. A fixed calendar window would drag swims from before the
/// drill existed in the swimmer's routine into `after`; the *latest* tap
/// would collapse `after` to nothing for anyone practising regularly; and
/// a window centred on the first tap discards usable history to buy an
/// arbitrary parameter.
///
/// **Statistic — per-swim presence of any targeted fault.** Each swim is
/// one yes/no: did any fault in `fixes` appear? A drill claims a cluster
/// (Catch-Up targets asymmetry *and* both overextensions), so the honest
/// question is whether that cluster showed up less, and yes/no-per-swim is
/// the same vocabulary `IssueTrend` already speaks on the History screen.
///
/// **Gate — three swims on each side, and a 34-point move.** No verdict is
/// offered until both sides hold `minSwims` swims. At that floor one swim
/// is worth 33 points of rate, which sits *below* `threshold`, so a
/// verdict always takes at least two swims' worth of movement — a single
/// good or bad day can never produce one. Deliberately conservative: a
/// swimmer may retune their training off this, so silence beats noise.
///
/// No significance test is run on purpose. Consecutive swims by one
/// swimmer are not independent draws, so a p-value here would be false
/// precision, and at these sample sizes an honest test would never speak.
enum DrillEffect {

    /// Sessions must clear this on BOTH sides before anything is claimed.
    static let minSwims = 3
    /// Rate change that counts as movement, in rate points. Sits just above
    /// one swim's worth at the minimum sample (1/3 = 0.333…), which is what
    /// forces a verdict to rest on two or more swims.
    static let threshold = 0.34

    /// One analyzed swim, reduced to what the comparison needs.
    struct Swim: Equatable {
        let date: Date
        let issueNames: [String]
        /// Empty means untagged, matching `SwimSession.swimmer`.
        let swimmer: String

        init(date: Date, issueNames: [String], swimmer: String = "") {
            self.date = date
            self.issueNames = issueNames
            self.swimmer = swimmer
        }
    }

    /// Why there is no read-out. Each case carries its own copy — the
    /// swimmer is told precisely what is missing and never shown a trend
    /// built on too little.
    enum Missing: Equatable {
        /// Drill has never been marked done, so there is no "started" date.
        case neverPractised
        /// No swim on either side ever contained a targeted fault.
        case faultNotSeen
        /// Fewer than `minSwims` swims predate the first practice. Terminal
        /// for this drill: a swim's `analyzedAt` never moves backwards.
        case tooFewBefore(have: Int)
        /// Fewer than `minSwims` swims since. Fills in with more swimming.
        case tooFewAfter(have: Int)
    }

    enum Verdict: Equatable {
        case lessOften
        case moreOften
        case unchanged
    }

    /// A measured comparison. Hit counts are carried alongside the verdict
    /// so the UI can show the swimmer the raw fractions it was derived
    /// from rather than an unfalsifiable badge.
    struct Readout: Equatable {
        let verdict: Verdict
        let beforeHits: Int
        let beforeTotal: Int
        let afterHits: Int
        let afterTotal: Int

        var beforeRate: Double { Double(beforeHits) / Double(beforeTotal) }
        var afterRate: Double { Double(afterHits) / Double(afterTotal) }
    }

    enum Result: Equatable {
        case notEnough(Missing)
        case measured(Readout)
    }

    /// The read-out for one drill.
    ///
    /// - Parameters:
    ///   - fixes: the drill's targeted FeedbackEngine issue names.
    ///   - practiceDates: every MARK DONE tap on this drill, any order.
    ///   - swims: every stored swim, any order. Callers must DROP legacy
    ///     rows they cannot resolve (see `isLegacyRow`) rather than pass
    ///     them in fault-free.
    ///   - activeSwimmer: identity scope; "" means everyone.
    static func result(fixes: [String],
                       practiceDates: [Date],
                       swims: [Swim],
                       activeSwimmer: String = "") -> Result {
        guard let started = practiceDates.min() else {
            return .notEnough(.neverPractised)
        }
        let scoped = scoped(swims, to: activeSwimmer)
        let targets = Set(fixes)
        func hits(_ swims: [Swim]) -> Int {
            swims.filter { !targets.isDisjoint(with: $0.issueNames) }.count
        }

        // Checked ahead of the sample gates: "this has never shown up" is
        // truer and more useful than "not enough swims" when there is
        // genuinely nothing to measure. Guarded on a non-empty scope so a
        // swimmer with no swims at all is not told a fault is absent.
        guard scoped.isEmpty || hits(scoped) > 0 else {
            return .notEnough(.faultNotSeen)
        }

        let before = scoped.filter { $0.date < started }
        let after = scoped.filter { $0.date >= started }
        // Before is reported first when both sides are short: it is the
        // side that can never fill in, so it is the more honest answer.
        guard before.count >= minSwims else {
            return .notEnough(.tooFewBefore(have: before.count))
        }
        guard after.count >= minSwims else {
            return .notEnough(.tooFewAfter(have: after.count))
        }

        let (beforeHits, afterHits) = (hits(before), hits(after))
        let delta = Double(afterHits) / Double(after.count)
            - Double(beforeHits) / Double(before.count)
        let verdict: Verdict = delta <= -threshold ? .lessOften
            : delta >= threshold ? .moreOften : .unchanged
        return .measured(Readout(verdict: verdict,
                                 beforeHits: beforeHits, beforeTotal: before.count,
                                 afterHits: afterHits, afterTotal: after.count))
    }

    /// Swims belonging to the active swimmer. Mirrors `HomeView`: "" is
    /// everyone, and a swimmer with no swims at all falls back to everyone
    /// rather than reporting a false "no baseline" on every card — the same
    /// stale-name guard the Home focus fault already uses, so the two
    /// surfaces cannot disagree about whose training they are describing.
    static func scoped(_ swims: [Swim], to swimmer: String) -> [Swim] {
        guard !swimmer.isEmpty else { return swims }
        let mine = swims.filter { $0.swimmer == swimmer }
        return mine.isEmpty ? swims : mine
    }

    /// True for a session saved before `SwimSession.issueNames` existed:
    /// the column migrated in empty while `issueCount` still records that
    /// faults were found. Callers resolve those from the result blob and
    /// DROP the ones that will not decode — reading an unresolvable swim
    /// as fault-free would manufacture an improvement out of a storage
    /// detail. Bounded to legacy rows, and drops to zero as the library
    /// turns over.
    static func isLegacyRow(issueNames: [String], issueCount: Int) -> Bool {
        issueNames.isEmpty && issueCount > 0
    }
}

// MARK: - Copy
//
// Lives beside the rule so the wording is unit-testable and so no view can
// quietly upgrade a correlation into a claim. Nothing here says a drill
// fixed anything: the strongest phrasing available is "since you started".

extension DrillEffect {
    /// "1 swim" / "4 swims".
    static func swimCount(_ n: Int) -> String {
        "\(n) swim\(n == 1 ? "" : "s")"
    }
}

extension DrillEffect.Missing {
    var headline: String {
        switch self {
        case .neverPractised: return "Not tracked yet"
        case .faultNotSeen:   return "Nothing to track"
        case .tooFewBefore:   return "No baseline"
        case .tooFewAfter:    return "Not enough swims yet"
        }
    }

    var detail: String {
        switch self {
        case .neverPractised:
            return "Mark it done once and the app starts watching these faults."
        case .faultNotSeen:
            return "The faults this drill targets haven't shown up in your swims."
        case .tooFewBefore(let have) where have == 0:
            return "No swims on record from before you started this drill, so there's nothing to compare against."
        case .tooFewBefore(let have):
            return "Only \(DrillEffect.swimCount(have)) on record from before you started this drill — \(DrillEffect.minSwims) needed to compare against."
        case .tooFewAfter(let have) where have == 0:
            return "No swims yet since you started this drill. Analyze \(DrillEffect.minSwims) and this fills in."
        case .tooFewAfter(let have):
            return "\(DrillEffect.swimCount(have)) since you started this drill — \(DrillEffect.minSwims) needed before a read-out."
        }
    }
}

extension DrillEffect.Readout {
    var headline: String {
        switch verdict {
        case .lessOften: return "Showing up less"
        case .moreOften: return "Showing up more"
        case .unchanged: return "About the same"
        }
    }

    /// The raw fractions the verdict came from.
    var detail: String {
        "In \(beforeHits) of \(DrillEffect.swimCount(beforeTotal)) before you started, "
            + "\(afterHits) of \(DrillEffect.swimCount(afterTotal)) since."
    }

    /// Shown only where a reader could misread the verdict as a cause.
    /// `.unchanged` makes no claim, so it carries none.
    var caveat: String? {
        verdict == .unchanged
            ? nil
            : "Timing only — plenty else changed too. Not proof the drill did it."
    }
}
