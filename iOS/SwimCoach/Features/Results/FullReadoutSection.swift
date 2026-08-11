import SwiftUI

/// "Full read-out" — every fault the model scores, with the strength it read
/// for each, grouped by where that reading landed relative to
/// `FeedbackEngine`'s bar.
///
/// Answers the question "3 issues found" leaves open: what about the other
/// seven, and was anything close? All ten channels have been persisted since
/// v1.1.0; until now nothing read the ones that didn't fire, so a fault at 42%
/// against a 45% bar rendered exactly like one at 14% — as absence.
///
/// Read-only over data already on disk. It computes no detection, changes no
/// threshold and stores nothing — the numbers here are the exact `Float`s
/// `FeedbackEngine.decode` was handed (see `FaultReadout`).
///
/// Hides itself entirely for legacy sessions with no stored windows, the same
/// way `IssueTimelineStrip` does — a zeroed ten-row table would be a
/// fabrication, not a degradation.
///
/// ── THE EDITORIAL PROBLEM ───────────────────────────────────────────────
/// A near miss is not a detection. The app looked at it and declined to flag
/// it, and no reader may be able to come away thinking otherwise. Four
/// independent signals say so, so that losing any one of them — a crop, a
/// screenshot, VoiceOver, colour blindness — still leaves three:
///
///   1. The band heading contains the words "not flagged".
///   2. The band caption states outright that nothing in it was detected.
///   3. The bar is painted in `inkTertiary`. Nothing under the bar is ever
///      painted in a severity hue anywhere in this app.
///   4. The row wears no `VerdictChip`. Flagged rows DO wear one, so the
///      absence is a stated negative rather than a neutral default.
///
/// And a fifth for VoiceOver, which can land on a row without ever hearing
/// the band: every close row's spoken label ends "Not a detected issue."
///
/// On (4) specifically — `VerdictChip`'s rule is that the mark means "we
/// measured this and here is the answer". For a near miss the answer is *no*,
/// and because the chip is tinted from the severity ramp, a chip on a near
/// miss would be pixel-identical to the mark the Issues section puts on a
/// real finding. That is the exact misread this section exists to avoid, so
/// the chip rides only on faults that cleared the bar.
struct FullReadoutSection: View {
    let windows: [IssueWindow]?
    /// The decoded issues. Used only to mark a flagged row in the severity the
    /// Issues section above already showed for the same fault.
    let issues: [TechniqueIssue]

    var body: some View {
        let rows = FaultReadout.ranked(from: windows ?? [])
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "Full read-out")
                    .padding(.bottom, 10)

                Text("Every fault the model checks, and how strongly it read "
                     + "each one. Strength is its average output across the clip, "
                     + "not a measure of how bad the fault is. The line is "
                     + "\(FaultReadout.percent(FaultReadout.flagBar))%.")
                    .font(.footnote)
                    .lineSpacing(3)
                    .foregroundStyle(DS.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)

                axis

                ForEach(FaultReadout.Band.allCases, id: \.self) { band in
                    let banded = rows.filter { $0.band == band }
                    if !banded.isEmpty {
                        bandHeader(band, count: banded.count)
                        card(banded)
                    }
                }
            }
            .padding(.bottom, 28)
        }
    }

    // MARK: - The line
    //
    // One label above the stack, aligned to the same x every row's threshold
    // tick sits at: the ticks then read as a single lane line ruled down the
    // section, and the bar only has to be named once. The horizontal inset
    // matches the card's own row padding so the axis and the meters below it
    // share an origin.

    @ScaledMetric(relativeTo: .caption2) private var axisHeight: CGFloat = 15
    @ScaledMetric(relativeTo: .caption2) private var axisTick: CGFloat = 8

    private var axis: some View {
        GeometryReader { geo in
            HStack(spacing: 4) {
                Rectangle()
                    .fill(DS.ink)
                    .frame(width: 1, height: axisTick)
                Text("\(FaultReadout.percent(FaultReadout.flagBar))%")
                    .font(.custom(GroteskWeight.medium.postScriptName,
                                  size: 9, relativeTo: .caption2))
                    .tracking(1.0)
                    .foregroundStyle(DS.inkSecondary)
                    .fixedSize()
                Spacer(minLength: 0)
            }
            .frame(height: geo.size.height, alignment: .bottom)
            .offset(x: geo.size.width * CGFloat(FaultReadout.flagBar))
        }
        .frame(height: axisHeight)
        .padding(.horizontal, Self.rowInset)
        .padding(.bottom, 6)
        // Spoken by the intro paragraph above, which names the same number.
        .accessibilityHidden(true)
    }

    // MARK: - Bands

    private func bandHeader(_ band: FaultReadout.Band, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("\(band.title.uppercased()) · \(count)")
                    .font(.sectionLabel)
                    .tracking(1.4)
                    .foregroundStyle(DS.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                LaneRule()
            }
            Text(band.caption)
                .font(.caption)
                .lineSpacing(2)
                .foregroundStyle(DS.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func card(_ banded: [FaultReadout]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(banded.enumerated()), id: \.element.id) { index, readout in
                FaultReadoutRow(readout: readout,
                                severity: severity(for: readout),
                                inset: Self.rowInset)
                if index < banded.count - 1 {
                    Rectangle().fill(DS.border).frame(height: 1)
                        .padding(.leading, Self.rowInset)
                        .accessibilityHidden(true)
                }
            }
        }
        .glassCard()
    }

    /// Prefer the decoded issue's own severity: `decode` escalates a fault's
    /// base severity above 0.8, so marking from the catalog base would show
    /// one word and colour here and a different one for the same fault in the
    /// Issues section directly above. Falls back to the catalog for the case
    /// that cannot happen (a flagged reading with no matching issue).
    private func severity(for readout: FaultReadout) -> TechniqueIssue.Severity {
        if let issue = issues.first(where: { $0.name == readout.name }) {
            return issue.severity
        }
        return FeedbackEngine.displayInfo(for: readout.name)?.severity ?? .minor
    }

    static let rowInset: CGFloat = 16
}

// MARK: - Row

private struct FaultReadoutRow: View {
    let readout: FaultReadout
    /// Only ever read for a flagged row — see `chip`.
    let severity: TechniqueIssue.Severity
    let inset: CGFloat

    /// The coloured bar itself.
    @ScaledMetric(relativeTo: .caption2) private var barHeight: CGFloat = 7
    /// The lane the bar sits in — taller, so the threshold line shows above
    /// and below it.
    @ScaledMetric(relativeTo: .caption2) private var meterHeight: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // `ViewThatFits` rather than wrapping in place: the horizontal
            // branch pins the name to one line (`fixedSize`) so a row that
            // cannot hold name + mark + number genuinely fails to fit and
            // stacks, instead of the name fracturing mid-word around a chip.
            // Same technique `SectionHeader(singleLine:)` documents.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    name.fixedSize()
                    Spacer(minLength: 8)
                    chip
                    percent
                }
                VStack(alignment: .leading, spacing: 6) {
                    name
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        chip
                        Spacer(minLength: 8)
                        percent
                    }
                }
            }

            meter

            if readout.showsPeak {
                Text("PEAK \(readout.peakPercent)%")
                    .font(.custom(GroteskWeight.medium.postScriptName,
                                  size: 9, relativeTo: .caption2))
                    .tracking(1.2)
                    .foregroundStyle(DS.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, inset)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var name: some View {
        Text(readout.displayName)
            .font(.grotesk(14, .medium))
            .foregroundStyle(readout.band == .clear ? DS.inkSecondary : DS.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var percent: some View {
        Text("\(readout.meanPercent)%")
            .font(.grotesk(15, .bold))
            .foregroundStyle(readout.band == .clear ? DS.inkTertiary : DS.ink)
            .fixedSize()
    }

    /// The house mark, on findings only.
    ///
    /// A flagged row is a fault the app reported: it is in `issues`, it is in
    /// the Issues section above, and `VerdictChip` is what this app says when
    /// it has an answer. Everything under the bar gets nothing — so the
    /// difference between a 45% row and a 44% row is a mark present or absent,
    /// a categorical break, not three points of bar length.
    ///
    /// It carries the severity word rather than "FLAGGED" so it says something
    /// the band heading does not already say, and says it in the same
    /// vocabulary the Issues section used for the same fault.
    @ViewBuilder
    private var chip: some View {
        if readout.band == .flagged {
            VerdictChip(text: severity.rawValue.uppercased(), tint: severityColor)
                .fixedSize()
                .accessibilityHidden(true)   // folded into the row's own label
        }
    }

    private var severityColor: Color {
        switch severity {
        case .major:    return DS.severityMajor
        case .moderate: return DS.severityModerate
        case .minor:    return DS.severityMinor
        }
    }

    // MARK: Meter
    //
    // Severity colour above the line, one neutral below it. Nothing under the
    // bar is ever painted in a severity hue anywhere in this app, so the
    // colour itself carries "this is not a finding" before any copy is read.
    //
    // Close and clear deliberately share that neutral rather than stepping
    // down the ink ladder. A close bar drawn in `inkSecondary` outweighed a
    // flagged minor fault's green one on screen — the not-a-finding reading
    // out-shouting the finding, which is the exact misread this section has
    // to avoid. Their band, caption and bar length already separate them.

    private var barColor: Color {
        readout.band == .flagged ? severityColor : DS.inkTertiary
    }

    /// The line is drawn full height BEHIND the track, so a flagged fill
    /// covers the stretch it crosses and only the stubs above and below the
    /// bar remain. That is deliberate, and it is a contrast decision as much
    /// as a visual one: drawn on top, the line would have to hold 3:1
    /// against every severity fill, and in dark — where those fills are
    /// bright coral, amber and spearmint — chalk ink measures 1.5–2.5:1
    /// against them. Behind the bar it only ever sits on the card or on the
    /// near-transparent `surface2` track, and the stubs still line the ten
    /// rows up into one ruled lane. Pinned by `ColorContrastTests`.
    private var meter: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(DS.ink)
                    .frame(width: 1, height: geo.size.height)
                    .offset(x: geo.size.width * CGFloat(FaultReadout.flagBar))

                ZStack(alignment: .leading) {
                    Rectangle().fill(DS.surface2)
                    Rectangle()
                        .fill(barColor)
                        .frame(width: max(1, geo.size.width * CGFloat(clampedMean)))
                }
                .frame(height: barHeight)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .offset(y: max(0, (geo.size.height - barHeight) / 2))
            }
        }
        .frame(height: meterHeight)
        .accessibilityHidden(true)
    }

    private var clampedMean: Float {
        readout.mean.isFinite ? min(max(readout.mean, 0), 1) : 0
    }

    // MARK: Spoken row
    //
    // The band caption is a separate element, so a VoiceOver user can land on
    // a row without having heard it — every close row therefore says it is
    // not a detection in its own label.

    private var accessibilityLabel: String {
        let bar = FaultReadout.percent(FaultReadout.flagBar)
        let peak = readout.showsPeak ? " Peaked at \(readout.peakPercent) percent." : ""
        switch readout.band {
        case .flagged:
            return "\(readout.displayName), flagged, \(severity.rawValue) severity. "
                + "\(readout.meanPercent) percent, at or above the \(bar) percent line.\(peak)"
        case .close:
            return "\(readout.displayName), close but not flagged. \(readout.meanPercent) "
                + "percent, under the \(bar) percent line. Not a detected issue.\(peak)"
        case .clear:
            return "\(readout.displayName), clear. \(readout.meanPercent) percent, "
                + "well under the \(bar) percent line.\(peak)"
        }
    }
}

// MARK: - Band copy
//
// The close band is the one that can be misread, so its wording never leaves
// the negative to inference: the heading itself says "not flagged", the
// caption states outright that nothing in the band was detected, and each
// row repeats it to VoiceOver. Cut-points are interpolated from
// `FaultReadout`, never typed twice.

private extension FaultReadout.Band {
    var title: String {
        switch self {
        case .flagged: return "Flagged"
        case .close:   return "Close, not flagged"
        case .clear:   return "Clear"
        }
    }

    var caption: String {
        let bar = FaultReadout.percent(FaultReadout.flagBar)
        let floor = FaultReadout.percent(FaultReadout.closeFloor)
        switch self {
        case .flagged:
            return "At or above the line. These are the issues listed above."
        case .close:
            return "Between \(floor)% and \(bar)% — under the line. "
                + "None of these was detected."
        case .clear:
            return "Under \(floor)%. The model found no sign of these."
        }
    }
}
