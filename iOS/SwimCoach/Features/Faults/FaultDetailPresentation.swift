import Foundation

/// Which of two registers the fault page speaks in.
///
/// v1.47.3 established the split on Drills: a measured verdict keeps the
/// scoreboard — the house `VerdictChip`, the label it answers, the numbers it
/// came from — and a case the app cannot judge drops that furniture entirely
/// and says so in a quiet line. `DrillEffectPresentation` pins that
/// distinction for the drill read-out; this is the same value for the two
/// findings a fault page makes on its own account: which way the fault is
/// showing up, and which way the model's confidence in it has moved.
///
/// Split out as a value, and out of every view body, for exactly the reason
/// the drill one was: a distinction that lives only in a `switch` inside
/// `body` is not one a test can hold on to, and the first time these two
/// registers were written they were one dim branch of the other.
///
/// The tone vocabulary is `DrillEffectPresentation.Tone` rather than a second
/// copy of it, so there stays exactly ONE tone-to-colour mapping in the app:
/// a fault receding is the same green here, on the drill card and on
/// History's arrow.
enum FaultDetailPresentation: Equatable {

    /// A finding the app stands behind. Wears a `VerdictChip` — which is
    /// what this app says when it has actually measured something.
    case verdict(label: String, arrow: String?,
                 tone: DrillEffectPresentation.Tone, detail: String?)

    /// No finding, and why not. Prose in the quietest ink tier: no chip, no
    /// answer column, no direction mark. A refusal to answer is not a muted
    /// answer, so it does not take the shape of one.
    case note(headline: String, detail: String)

    /// True where a `VerdictChip` is allowed. Reads as a rule at call sites
    /// and lets a test say the thing that matters out loud.
    var isMeasured: Bool {
        if case .verdict = self { return true }
        return false
    }
}

// MARK: - Recurrence

extension FaultDetailPresentation {

    /// Which way the fault is showing up, over the scoped library.
    ///
    /// `IssueTrend.trend` answers `.flat` for two situations that are not the
    /// same thing: it compared the halves and they matched, and it declined
    /// to look because the library is under `minSessions`. On a page whose
    /// whole job is to say what is known, those must not render alike — so
    /// the library size is tested HERE, before the trend is read, and the
    /// short library gets the quiet register instead of a missing chip.
    ///
    /// A measured no-movement keeps its chip and says ABOUT THE SAME, the
    /// same words the drill card uses for the same finding.
    static func recurrence(_ summary: FaultHistory.Summary) -> FaultDetailPresentation {
        guard summary.totalSwims >= IssueTrend.minSessions else {
            return .note(
                headline: "Too little history to call it",
                detail: "\(DrillEffect.swimCount(summary.totalSwims)) on record — "
                    + "\(IssueTrend.minSessions) needed before the app will say which "
                    + "way this is going.")
        }
        switch summary.trend {
        case .improving:
            return .verdict(label: "SHOWING UP LESS", arrow: "arrow.down.right",
                            tone: .receding, detail: nil)
        case .worsening:
            return .verdict(label: "SHOWING UP MORE", arrow: "arrow.up.right",
                            tone: .advancing, detail: nil)
        case .flat:
            return .verdict(label: "ABOUT THE SAME", arrow: nil,
                            tone: .flat, detail: nil)
        }
    }
}

// MARK: - Detection strength

extension FaultDetailPresentation {

    /// Which way the model's confidence has moved.
    ///
    /// The chart and the verdict have different gates on purpose: a line is
    /// evidence and draws from two readings, a verdict is a claim and needs
    /// `FaultHistory.minStrengthSamples`. Between those two numbers the page
    /// draws the line AND says, in the quiet register, that it will not call
    /// it yet — otherwise a chart with no words under it is left to be read
    /// as a verdict nobody made.
    static func strength(_ summary: FaultHistory.Summary) -> FaultDetailPresentation {
        guard let shift = summary.strength else {
            return .note(headline: shortHeadline(summary.plottable.count),
                         detail: shortDetail(summary.plottable.count))
        }
        let (arrow, tone): (String?, DrillEffectPresentation.Tone)
        switch shift.move {
        case .easing:   (arrow, tone) = ("arrow.down.right", .receding)
        case .building: (arrow, tone) = ("arrow.up.right", .advancing)
        case .steady:   (arrow, tone) = (nil, .flat)
        }
        return .verdict(label: shift.headline, arrow: arrow,
                        tone: tone, detail: shift.detail)
    }

    private static func shortHeadline(_ readings: Int) -> String {
        switch readings {
        case 0:  return "No readings on record"
        case 1:  return "One reading so far"
        default: return "Not enough readings yet"
        }
    }

    private static func shortDetail(_ readings: Int) -> String {
        switch readings {
        case 0:
            // Reachable only where the fault WAS found and none of those
            // swims' stored results will still decode. The page counts those
            // appearances all the same — dropping them would invent an
            // improvement — so it has to explain the empty chart.
            return "None of the swims it appeared in have a stored result the app "
                + "can still read, so there is nothing to plot."
        case 1:
            return "A line needs two readings, and a call on the direction needs "
                + "\(FaultHistory.minStrengthSamples)."
        default:
            return "\(readings) readings where this was found — "
                + "\(FaultHistory.minStrengthSamples) needed before the app will say "
                + "which way the model's confidence is going."
        }
    }
}
