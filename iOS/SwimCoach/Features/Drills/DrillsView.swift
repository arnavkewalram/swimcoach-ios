import SwiftUI
import SwiftData

/// The drill library: editorial index cards grouped by focus area. When
/// opened from an issue row, the drills that fix that issue are outlined
/// in lane blue and scrolled into view.
struct DrillsView: View {
    /// FeedbackEngine issue name to spotlight, if arriving from Results.
    var highlightIssue: String? = nil
    @Environment(\.modelContext) private var modelContext
    @Query private var practiceEvents: [DrillPracticeEvent]
    @Query private var sessions: [SwimSession]
    @AppStorage("activeSwimmer") private var activeSwimmer: String = ""
    /// Swims reduced to (date, faults, swimmer) for the "is it working?"
    /// read-out. Hoisted into state and refreshed on appearance because
    /// resolving legacy rows can decode result blobs — nothing behind this
    /// screen writes a session, so once per visit is enough.
    ///
    /// `nil` until that first pass runs. An empty array here would be read
    /// as "this swimmer has no swims", which is a claim about their history
    /// rather than about a load that has not happened yet.
    @State private var swims: [DrillEffect.Swim]? = nil

    private var highlightedIDs: Set<String> {
        guard let issue = highlightIssue else { return [] }
        return Set(DrillCatalog.drills(fixing: issue).map(\.id))
    }

    /// Whose practice this screen is describing. Resolved off the session
    /// list rather than `swims` so it is stable before the first load, and
    /// by the same rule `DrillEffect` applies to the read-out.
    private var scope: String {
        DrillEffect.resolvedScope(activeSwimmer, knownSwimmers: sessions.map(\.swimmer))
    }

    /// This swimmer's taps — everything the cards count.
    private var scopedEvents: [DrillPracticeEvent] {
        DrillPractice.scoped(practiceEvents, to: scope)
    }

    /// Of the fixing drills, the one most due for practice — the scroll
    /// target and START HERE card.
    private var startHereID: String? {
        guard let issue = highlightIssue else { return nil }
        return DrillPractice.leastRecentlyPracticed(
            of: DrillCatalog.drills(fixing: issue).map(\.id),
            events: scopedEvents)
    }

    /// Stored swims in `DrillEffect`'s vocabulary. Sessions saved before
    /// the `issueNames` column existed migrate in empty, so those rows
    /// alone fall back to the result blob; ones that will not decode are
    /// DROPPED rather than read as fault-free — a swim counted clean
    /// because its blob is unreadable would invent an improvement.
    private func refreshSwims() {
        swims = sessions.compactMap { session in
            guard DrillEffect.isLegacyRow(issueNames: session.issueNames,
                                          issueCount: session.issueCount) else {
                return DrillEffect.Swim(date: session.analyzedAt,
                                        issueNames: session.issueNames,
                                        swimmer: session.swimmer)
            }
            guard let names = session.decoded()?.issues.map(\.name) else { return nil }
            return DrillEffect.Swim(date: session.analyzedAt,
                                    issueNames: names,
                                    swimmer: session.swimmer)
        }
    }

    /// The card's read-out, or nil while there is nothing honest to say.
    ///
    /// Taps go in unfiltered: `DrillEffect.result` scopes them and the
    /// swims together, so the boundary and the statistic are one swimmer's.
    ///
    /// Static and value-only so the withheld-until-loaded rule is testable
    /// without standing up the view.
    static func readout(for drill: Drill,
                        events: [DrillPracticeEvent],
                        swims: [DrillEffect.Swim]?,
                        activeSwimmer: String) -> DrillEffect.Result? {
        let result = DrillEffect.result(
            fixes: drill.fixes,
            practices: events.compactMap {
                $0.drillID == drill.id
                    ? DrillEffect.Practice(date: $0.date, swimmer: $0.swimmer)
                    : nil
            },
            swims: swims ?? [],
            activeSwimmer: activeSwimmer)
        // Before the swims land, the only answer that does not depend on
        // them is "never marked done" — every other one would be a sentence
        // about the swimmer's history built from an empty array.
        guard swims != nil || result == .notEnough(.neverPractised) else { return nil }
        return result
    }

    private func effect(for drill: Drill) -> DrillEffect.Result? {
        Self.readout(for: drill,
                     events: practiceEvents,
                     swims: swims,
                     activeSwimmer: activeSwimmer)
    }

    var body: some View {
        ZStack {
            DS.background.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Every fault the analysis can detect maps to a drill here. Fold two or three into each warm-up. Once a drill is marked done, its card tracks how often the faults it targets showed up before and since.")
                            .font(.footnote)
                            .lineSpacing(3)
                            .foregroundStyle(DS.inkSecondary)
                            .padding(.top, 8)

                        ForEach(DrillFocus.allCases, id: \.self) { focus in
                            let drills = DrillCatalog.all.filter { $0.focus == focus }
                            SectionHeader(title: focus.rawValue)
                                .padding(.top, 6)
                            ForEach(drills) { drill in
                                DrillCard(
                                    number: cardNumber(of: drill),
                                    drill: drill,
                                    isHighlighted: highlightedIDs.contains(drill.id),
                                    isStartHere: drill.id == startHereID,
                                    practice: DrillPractice.summary(
                                        for: drill.id, events: scopedEvents),
                                    effect: effect(for: drill),
                                    onMarkDone: {
                                        // Stamped with the swimmer the rest
                                        // of the screen is scoped to — the
                                        // resolved one, so a stale name is
                                        // recorded as the "everyone" the
                                        // card was actually showing.
                                        modelContext.insert(
                                            DrillPracticeEvent(drillID: drill.id,
                                                               swimmer: scope))
                                        Haptics.tap()
                                    })
                                    .id(drill.id)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
                .onAppear {
                    refreshSwims()
                    if let target = startHereID
                        ?? DrillCatalog.all.first(where: { highlightedIDs.contains($0.id) })?.id {
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                    }
                }
            }
        }
        .navigationTitle("Drills")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Drills")
                    .font(.grotesk(17, .medium))
                    .foregroundStyle(DS.ink)
            }
        }
        .toolbarBackground(DS.background, for: .navigationBar)
    }

    private func cardNumber(of drill: Drill) -> String {
        let idx = (DrillCatalog.all.firstIndex(of: drill) ?? 0) + 1
        return String(format: "%02d", idx)
    }
}

// MARK: - Drill index card

private struct DrillCard: View {
    let number: String
    let drill: Drill
    let isHighlighted: Bool
    var isStartHere: Bool = false
    let practice: DrillPractice.Summary
    /// nil while the swim history is still loading — the row stays away
    /// rather than claiming a history nobody has read yet.
    let effect: DrillEffect.Result?
    let onMarkDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(number)
                    .font(.grotesk(13, .bold))
                    .foregroundStyle(isHighlighted ? DS.accent : DS.inkTertiary)
                Text(drill.name)
                    .font(.grotesk(17, .bold))
                    .foregroundStyle(DS.ink)
                if isStartHere {
                    Text("START HERE")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 8))
                        .tracking(1.2)
                        .foregroundStyle(DS.onAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(DS.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .fixedSize()
                }
                Spacer()
                Text(drill.dose.uppercased())
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                    .tracking(0.8)
                    .foregroundStyle(DS.inkSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(DS.border, lineWidth: 1))
            }

            Text(drill.goal)
                .font(.footnote)
                .lineSpacing(3)
                .foregroundStyle(DS.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(drill.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)")
                            .font(.grotesk(11, .bold))
                            .foregroundStyle(DS.accent)
                            .frame(width: 14, alignment: .trailing)
                            .padding(.top, 1)
                        Text(step)
                            .font(.footnote)
                            .lineSpacing(2)
                            .foregroundStyle(DS.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                    if i < drill.steps.count - 1 {
                        Rectangle().fill(DS.border).frame(height: 1)
                            .padding(.leading, 24)
                    }
                }
            }

            if let effect {
                DrillEffectRow(effect: effect)
            }

            HStack {
                if practice.count > 0, let last = practice.lastDate {
                    Text("PRACTICED \(practice.count)× · LAST \(last.formatted(.dateTime.day().month()).uppercased())")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                        .tracking(1.0)
                        // A tally, not a verdict. It used to be pine green —
                        // the same token SHOWING UP LESS wears — so a plain
                        // count of taps read as good news about the swimmer's
                        // faults. Whether the drill is working is the row
                        // above's job, and only it gets to answer in colour.
                        .foregroundStyle(DS.inkTertiary)
                }
                Spacer()
                Button(action: onMarkDone) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .accessibilityHidden(true)
                        Text("MARK DONE")
                            .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                            .tracking(1.2)
                    }
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(DS.accent.opacity(0.45), lineWidth: 1))
                    // Pill stays visually compact; the frame extends the
                    // tap target to the HIG 44pt minimum.
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark \(drill.name) done today")
            }
            .padding(.top, 2)
        }
        .padding(16)
        .glassCard(borderColor: isHighlighted ? DS.accent : DS.border)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - "Is it working?" presentation
//
// Which of two registers the read-out speaks in. Split out as a value so
// the distinction is pinned by a test rather than by whichever branch of a
// view body happened to run: `.measured` and `.notEnough` used to render
// byte-identically — ABOUT THE SAME and NOT ENOUGH SWIMS YET both landed on
// RGB(60,66,75) — so a statistical answer and a refusal to give one were
// indistinguishable. `DrillEffect`'s whole posture is that silence beats
// noise; that has to be visible, or the honesty is only in the source.

enum DrillEffectPresentation: Equatable {
    /// A measured finding. Wears the app's `VerdictChip`, because the chip
    /// is what this app says when it has actually measured something.
    case verdict(label: String, arrow: String?, tone: Tone,
                 detail: String, caveat: String?)
    /// No verdict, and why not. Prose in the quietest ink tier: no rule, no
    /// question label, no answer column, no chip. A refusal to answer is
    /// not a muted answer, so it does not take the shape of one.
    case note(headline: String, detail: String)

    /// Semantic tint, kept out of `Color` so the mapping stays comparable.
    enum Tone: Equatable { case receding, advancing, flat }

    static func of(_ effect: DrillEffect.Result) -> Self {
        switch effect {
        case .notEnough(let missing):
            return .note(headline: missing.headline, detail: missing.detail)
        case .measured(let readout):
            // Direction marks reuse the History chart's vocabulary: down-right
            // for a fault receding, up-right for one advancing, no mark at all
            // when nothing moved.
            let (arrow, tone): (String?, Tone)
            switch readout.verdict {
            case .lessOften: (arrow, tone) = ("arrow.down.right", .receding)
            case .moreOften: (arrow, tone) = ("arrow.up.right", .advancing)
            case .unchanged: (arrow, tone) = (nil, .flat)
            }
            return .verdict(label: readout.headline, arrow: arrow, tone: tone,
                            detail: readout.detail, caveat: readout.caveat)
        }
    }
}

extension DrillEffectPresentation.Tone {
    var color: Color {
        switch self {
        case .receding:  return DS.severityMinor
        case .advancing: return DS.severityMajor
        // Compare tints its own SAME chip `inkTertiary`; a measured
        // non-result reads the same way on both screens.
        case .flat:      return DS.inkTertiary
        }
    }
}

// MARK: - "Is it working?" read-out
//
// The loop-closer: how often this drill's targeted faults appeared before
// the swimmer first marked it done versus since. Presentational only — the
// rule, the sample gates and every word of copy live in `DrillEffect`, so
// this file cannot quietly turn a correlation into a claim.
private struct DrillEffectRow: View {
    let effect: DrillEffect.Result

    /// Matches `VerdictChip`'s capped growth so the question and its answer
    /// stay on one typographic level at accessibility sizes.
    @ScaledMetric(relativeTo: .caption2) private var scaledLabel: CGFloat = VerdictChip.baseSize
    private var labelSize: CGFloat { min(scaledLabel, VerdictChip.maxSize) }

    var body: some View {
        switch DrillEffectPresentation.of(effect) {
        case .note(let headline, let detail):
            // No scoreboard to draw: the app has nothing to report, and a
            // note in the margin is the honest shape for saying so.
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.footnote.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .lineSpacing(2)
            }
            .foregroundStyle(DS.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)

        case .verdict(let label, let arrow, let tone, let detail, let caveat):
            VStack(alignment: .leading, spacing: 6) {
                Rectangle().fill(DS.border).frame(height: 1)
                    .accessibilityHidden(true)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        question
                        Spacer(minLength: 10)
                        chip(label, arrow, tone)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        question
                        chip(label, arrow, tone)
                    }
                }
                Text(detail)
                    .font(.footnote)
                    .lineSpacing(2)
                    .foregroundStyle(DS.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let caveat {
                    Text(caveat)
                        .font(.caption2)
                        .foregroundStyle(DS.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 2)
        }
    }

    private var question: some View {
        Text("IS IT WORKING?")
            .font(.custom(GroteskWeight.medium.postScriptName, size: labelSize))
            .tracking(1.2)
            .foregroundStyle(DS.inkTertiary)
            .fixedSize()
    }

    private func chip(_ label: String, _ arrow: String?,
                      _ tone: DrillEffectPresentation.Tone) -> some View {
        VerdictChip(text: label.uppercased(), icon: arrow, tint: tone.color)
            .fixedSize()
            // Spoken as authored — the caps are a typographic register, not
            // an acronym, and VoiceOver need not shout them.
            .accessibilityLabel(label)
    }
}
