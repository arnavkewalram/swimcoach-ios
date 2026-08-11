import SwiftUI
import Charts

// MARK: - The two registers, rendered
//
// Every card below asks `FaultDetailPresentation` which register it is in and draws
// that shape. Neither the wording nor the choice is made here — see
// `FaultDetailPresentation` for why the decision is a value and not a branch of a body.

/// A measured finding: the house chip, tinted, spoken as authored.
struct FaultVerdictChip: View {
    let label: String
    let arrow: String?
    let tone: DrillEffectPresentation.Tone

    var body: some View {
        VerdictChip(text: label.uppercased(), icon: arrow, tint: tone.color)
            .fixedSize()
            // The caps are a typographic register, not an acronym.
            .accessibilityLabel(label.capitalized)
    }
}

/// A refusal: two lines of prose in the quietest ink tier. No rule, no
/// label, no answer column, no chip — the same shape `DrillEffectRow` draws
/// for the same situation, so the two screens agree about what "we don't
/// know" looks like.
struct FaultNote: View {
    let headline: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(headline)
                .font(.footnote.weight(.semibold))
            Text(detail)
                .font(.caption2)
                .lineSpacing(2)
        }
        .foregroundStyle(DS.inkTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Recurrence

/// How often, and where it stands now. Three measured cells in History's
/// summary-strip language, then the sentence Home's Focus panel makes, then
/// whichever register the presence trend has earned.
struct RecurrenceCard: View {
    let summary: FaultHistory.Summary
    let ruleHeight: CGFloat
    @Environment(\.dynamicTypeSize) private var typeSize

    private var readout: FaultDetailPresentation { .recurrence(summary) }

    /// The three facts, once — both layouts below render from this list.
    /// Counts and dates, not verdicts: they are what the app read off the
    /// library, so they stay in full ink in either register.
    private var stats: [(label: String, value: String)] {
        [("SEEN IN", "\(summary.seenCount)/\(summary.totalSwims)"),
         ("FIRST SEEN", Self.short(summary.firstSeen?.date)),
         ("LAST SEEN", Self.short(summary.lastSeen?.date))]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // "How often" and not "Recurrence": at accessibility sizes the
            // stacked branch lets a title wrap, and RECURRENCE is a single
            // word wide enough to break inside itself ("RECURRENC / E").
            // Two short words break between them instead, and the plainer
            // phrasing sits better beside this page's other headers.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    SectionHeader(title: "How often", singleLine: true)
                    chip
                }
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "How often")
                    chip
                }
            }

            // Three columns is a density choice that stops paying at
            // accessibility sizes: at AX5 the labels grow until FIRST SEEN
            // and LAST SEEN meet with no gap between them and read as one
            // word. Above the boundary the same three facts become rows.
            if typeSize.isAccessibilitySize {
                stackedStats
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                        if index > 0 { divider }
                        cell(value: stat.value, label: stat.label)
                    }
                }
                .padding(.vertical, 2)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.recentLine)
                    .font(.grotesk(15, .medium))
                    .foregroundStyle(DS.ink)
                if let standing = summary.standingLine {
                    Text(standing)
                        .font(.footnote)
                        .foregroundStyle(DS.inkSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            // The refusal, when the library is too short for `IssueTrend` to
            // speak. It lands under the counts rather than beside the header
            // because it is a sentence, not an answer to a label.
            if case .note(let headline, let detail) = readout {
                FaultNote(headline: headline, detail: detail)
            }
        }
        .padding(16)
        .glassCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var chip: some View {
        if case .verdict(let label, let arrow, let tone, _) = readout {
            FaultVerdictChip(label: label, arrow: arrow, tone: tone)
        }
    }

    private var stackedStats: some View {
        VStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                if index > 0 {
                    Rectangle().fill(DS.border).frame(height: 1)
                        .accessibilityHidden(true)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(stat.label)
                        .font(.statUnit)
                        .tracking(1.1)
                        .foregroundStyle(DS.inkTertiary)
                    Spacer(minLength: 8)
                    Text(stat.value)
                        .font(.grotesk(18, .bold))
                        .foregroundStyle(DS.ink)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(DS.border).frame(width: 1, height: ruleHeight)
    }

    private func cell(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.grotesk(18, .bold))
                .foregroundStyle(DS.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.statUnit)
                .tracking(1.1)
                .foregroundStyle(DS.inkTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        // Breathing room so neighbouring labels cannot touch across the
        // hairline even at the largest non-accessibility size.
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
    }

    /// "12 Mar" — the date shape History's rows use, or an em dash.
    private static func short(_ date: Date?) -> String {
        date.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? "—"
    }

    private var accessibilityLabel: String {
        var label = "How often. Seen in \(summary.seenCount) of "
            + "\(DrillEffect.swimCount(summary.totalSwims))."
        if let first = summary.firstSeen {
            label += " First seen \(first.date.formatted(date: .abbreviated, time: .omitted))."
        }
        label += " \(summary.recentLine)"
        if let standing = summary.standingLine { label += " \(standing)" }
        switch readout {
        case .verdict(let text, _, _, _): label += " \(text.capitalized)."
        case .note(let headline, let detail): label += " \(headline). \(detail)"
        }
        return label
    }
}

// MARK: - Detection strength

/// The model's confidence, each time it found the fault. The one series on
/// this page that exists nowhere else in the app: `observedValue` has been
/// written on every issue of every session since the model shipped and read
/// only by the two-session comparison.
struct StrengthCard: View {
    let summary: FaultHistory.Summary
    let height: CGFloat

    private var readout: FaultDetailPresentation { .strength(summary) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Detection strength")

            // The chart is evidence, not a claim, so it draws on its own
            // gate — two readings — and the verdict below keeps its own.
            if summary.isStrengthPlottable {
                Text("How sure the model was each time it found this. "
                     + "Dashed line = the \(FaultHistory.percent(Double(FeedbackEngine.threshold))) "
                     + "flag threshold.")
                    .font(.caption)
                    .foregroundStyle(DS.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                chart
            }

            switch readout {
            case .verdict(let label, let arrow, let tone, let detail):
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        detailText(detail)
                        Spacer(minLength: 8)
                        FaultVerdictChip(label: label, arrow: arrow, tone: tone)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        detailText(detail)
                        FaultVerdictChip(label: label, arrow: arrow, tone: tone)
                    }
                }
            case .note(let headline, let detail):
                FaultNote(headline: headline, detail: detail)
            }
        }
        .padding(16)
        .glassCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func detailText(_ detail: String?) -> some View {
        if let detail {
            Text(detail)
                .font(.footnote)
                .foregroundStyle(DS.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Gapped series, `MetricTrend`-style: contiguity runs get their own
    /// `series:` key so the line breaks at a reading that could not be
    /// taken instead of drawing straight through it.
    private var chart: some View {
        Chart {
            ForEach(summary.plottable) { point in
                LineMark(
                    x: .value("Swim", point.swimIndex),
                    y: .value("Confidence", point.strength ?? 0),
                    series: .value("Run", point.run)
                )
                .foregroundStyle(DS.accent)

                PointMark(
                    x: .value("Swim", point.swimIndex),
                    y: .value("Confidence", point.strength ?? 0)
                )
                .foregroundStyle(DS.gradeColor(point.grade))
                .symbolSize(46)
            }

            RuleMark(y: .value("Flag threshold", Double(FeedbackEngine.threshold)))
                .foregroundStyle(DS.inkTertiary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .chartYScale(domain: 0...1)
        // Pinned to real swim indices, like the score trend — `.automatic`
        // invents negative "swims" when the plot gets narrow at large type.
        .chartXScale(domain: 0.5...(Double(summary.totalSwims) + 0.5))
        .chartXAxis {
            AxisMarks(values: Array(stride(
                from: 1, through: summary.totalSwims,
                by: max(1, summary.totalSwims / 5)))) { _ in
                AxisGridLine().foregroundStyle(DS.border.opacity(0.6))
                AxisTick().foregroundStyle(Color.clear)
                AxisValueLabel()
                    .foregroundStyle(DS.inkTertiary)
                    .font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(values: [0, 0.5, 1.0]) { value in
                AxisGridLine().foregroundStyle(DS.border.opacity(0.6))
                AxisValueLabel {
                    Text(FaultHistory.percent(value.as(Double.self) ?? 0))
                        .font(.caption2)
                        .foregroundStyle(DS.inkTertiary)
                }
            }
        }
        .frame(height: height)
    }

    private var accessibilityLabel: String {
        var label = "Detection strength."
        if summary.isStrengthPlottable {
            label += " Charted across \(DrillEffect.swimCount(summary.plottable.count))"
                + " where this was found."
        }
        switch readout {
        case .verdict(let text, _, _, let detail):
            if let detail { label += " \(detail)" }
            label += " \(text.capitalized)."
        case .note(let headline, let detail):
            label += " \(headline). \(detail)"
        }
        return label
    }
}

// MARK: - One swim it appeared in

struct AppearanceRow: View {
    let appearance: FaultHistory.Appearance
    /// False where the swim's stored result will not decode. Such a row is
    /// still shown — the appearance is real and counts — but it does not
    /// pretend to be a way through, because there is nothing to open.
    let isOpenable: Bool

    private var strengthText: String {
        appearance.strength.map(FaultHistory.percent) ?? "—"
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(appearance.name.isEmpty
                     ? appearance.date.formatted(date: .abbreviated, time: .shortened)
                     : appearance.name)
                    .font(.grotesk(15, .medium))
                    .foregroundStyle(DS.ink)
                    .multilineTextAlignment(.leading)
                Text("Swim \(appearance.swimIndex) · score \(appearance.score) · grade \(appearance.grade)")
                    .font(.caption)
                    .foregroundStyle(DS.inkSecondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(strengthText)
                    .font(.grotesk(15, .bold))
                    .foregroundStyle(DS.ink)
                Text("SURE")
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                    .tracking(1.0)
                    .foregroundStyle(DS.inkTertiary)
            }

            if isOpenable {
                Image(systemName: "arrow.right")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(DS.inkTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard()
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                .fill(DS.gradeColor(appearance.grade))
                .frame(width: 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let head = "\(appearance.date.formatted(date: .abbreviated, time: .omitted)), "
            + "score \(appearance.score), grade \(appearance.grade)"
        guard isOpenable else {
            return head + ". This swim's saved results can no longer be opened."
        }
        return head + ", detected at \(strengthText) confidence. Opens full results."
    }
}

// MARK: - Drill read-out, compact

/// The drill library's verdict, in one line. Every word comes from
/// `DrillEffect` — this file decides layout and nothing else, so the fault
/// page cannot quietly claim more than the drill card does.
struct DrillEffectSummaryRow: View {
    let drill: Drill
    /// nil while the swim history is still loading.
    let effect: DrillEffect.Result?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Structural: this rule separates one drill from the next, not
            // the read-out from its label. A refusal drops the read-out's
            // own furniture (below), not the list's.
            Rectangle().fill(DS.border).frame(height: 1)
                .accessibilityHidden(true)
            if let presentation = effect.map(DrillEffectPresentation.of) {
                readout(presentation)
            } else {
                name
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func readout(_ presentation: DrillEffectPresentation) -> some View {
        switch presentation {
        case .verdict(let label, let arrow, let tone, let detail, _):
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    name
                    Spacer(minLength: 10)
                    FaultVerdictChip(label: label, arrow: arrow, tone: tone)
                }
                VStack(alignment: .leading, spacing: 5) {
                    name
                    FaultVerdictChip(label: label, arrow: arrow, tone: tone)
                }
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(DS.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

        case .note(let headline, let detail):
            // Nothing was measured, so nothing takes the shape of a
            // finding. Same split `DrillsView` draws.
            name
            FaultNote(headline: headline, detail: detail)
        }
    }

    private var name: some View {
        Text(drill.name)
            .font(.grotesk(14, .medium))
            .foregroundStyle(DS.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}
