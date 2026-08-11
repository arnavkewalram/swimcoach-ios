import SwiftUI
import SwiftData

/// One fault's own page.
///
/// History can already say "Body Sag appeared in 9 of 12 swims, and it's
/// worsening" and then offer nowhere to ask anything further. This is the
/// further: when the fault started, where it stands now, how sure the model
/// has been each time it found it, which swims carried it, and what to do
/// about it.
///
/// ── Where the decode happens ────────────────────────────────────────────
///
/// `TechniqueIssue.observedValue` — the per-swim confidence this page plots
/// — lives only inside the externally-stored result blob, so reading it
/// costs a disk read plus a full JSON pass over the session's keypoint
/// frames. Twice now this app has shipped a fix for doing that inside
/// something SwiftUI re-invokes (v1.43.4, v1.45.5), so:
///
///   • the decode runs in `load()`, called from `.onAppear` only — never
///     from a computed property, never from `body`;
///   • it opens a blob ONLY for the swims that need one: the swims whose
///     stored `issueNames` column names this fault, plus legacy rows whose
///     column migrated in empty. Every other swim is read from columns, so
///     a library of a hundred clean swims costs zero decodes;
///   • everything the page renders is derived once, at load, into a single
///     `Readout` — the body does no aggregation.
///
/// ── Withheld until read ─────────────────────────────────────────────────
///
/// `readout` is `nil` until that pass finishes, and the page shows nothing
/// about the swimmer's history until it is non-nil. An empty summary would
/// be a claim ("never seen in your swims"); nil is the absence of one.
/// Same discipline v1.47.1 gave `DrillsView`.
///
/// ── Whose history ───────────────────────────────────────────────────────
///
/// `activeSwimmer`, resolved and applied by `DrillEffect`'s one rule inside
/// `FaultHistory.summary` — so the first-seen date, the recent window, the
/// strength series, the swim list and the drill read-outs below are all the
/// same person's. Swims go in UNFILTERED for that reason: pre-scoping them
/// here would be the second scoping rule `DrillEffect`'s header warns
/// against. The scope is named in the masthead whenever it is a named
/// swimmer, because every sentence on this page is in the second person.
struct FaultDetailView: View {
    /// Raw `FeedbackEngine` issue name.
    let faultName: String

    @Environment(AppRouter.self) private var router
    @Query(sort: \SwimSession.analyzedAt, order: .reverse) private var sessions: [SwimSession]
    @Query private var practiceEvents: [DrillPracticeEvent]
    @AppStorage("activeSwimmer") private var activeSwimmer: String = ""

    /// Everything the page claims, derived in one pass on appearance.
    /// `nil` until that pass has run — see the type doc.
    @State private var readout: Readout? = nil

    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 168
    @ScaledMetric(relativeTo: .caption2) private var ruleHeight: CGFloat = 34

    /// The single derived payload. Held together so the body cannot end up
    /// rendering a summary built from one load and drills from another.
    private struct Readout {
        let summary: FaultHistory.Summary
        /// The same swims in `DrillEffect`'s vocabulary, so the drill
        /// read-outs on this page and on the drill library agree.
        let drillSwims: [DrillEffect.Swim]
    }

    private var entry: (display: String, severity: TechniqueIssue.Severity,
                        description: String, tip: String)? {
        FeedbackEngine.catalogEntry(for: faultName)
    }

    private var title: String { entry?.display ?? faultName }

    private var severityColor: Color {
        switch entry?.severity {
        case .major:    return DS.severityMajor
        case .moderate: return DS.severityModerate
        default:        return DS.severityMinor
        }
    }

    /// Whose history this is. Resolved off the session list, by the same
    /// rule `FaultHistory` applies inside the summary, so the tag and the
    /// numbers can never name different people.
    private var scope: String {
        DrillEffect.resolvedScope(activeSwimmer, knownSwimmers: sessions.map(\.swimmer))
    }

    var body: some View {
        ZStack {
            DS.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    masthead

                    if let readout {
                        if let empty = readout.summary.empty {
                            emptyState(empty.headline, empty.detail)
                        } else {
                            RecurrenceCard(summary: readout.summary, ruleHeight: ruleHeight)
                            StrengthCard(summary: readout.summary, height: chartHeight)
                            appearancesCard(readout.summary)
                        }
                        drillsCard(readout)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
            .scrollContentBackground(.hidden)
        }
        // The one decode pass. Not `.task(id:)` and not a computed property
        // — see the type doc.
        .onAppear(perform: load)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(.grotesk(17, .medium))
                    .foregroundStyle(DS.ink)
                    .lineLimit(1)
            }
        }
        .toolbarBackground(DS.background, for: .navigationBar)
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.grotesk(28, .bold))
                .foregroundStyle(DS.ink)
                .fixedSize(horizontal: false, vertical: true)
            // Badges wrap to their own line before they squeeze the title.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { badges }
                VStack(alignment: .leading, spacing: 6) { badges }
            }
            if let description = entry?.description {
                Text(description)
                    .font(.footnote)
                    .lineSpacing(3)
                    .foregroundStyle(DS.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(.leading, 14)
        // The severity rule, running the height of the masthead — the same
        // leading-edge mark History's session rows carry.
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(severityColor)
                .frame(width: 3)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var badges: some View {
        SeverityBadge(severity: (entry?.severity ?? .minor).rawValue)
        if !scope.isEmpty {
            // The house swimmer tag — tracked caps in lane blue, exactly as
            // History's rows and Results' header wear it. Deliberately NOT
            // outlined: an outlined tracked chip is `VerdictChip`, the mark
            // this app reserves for something it measured, and whose swims
            // these are is a filter, not a finding.
            Text(scope.uppercased())
                .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                .tracking(1.0)
                .foregroundStyle(DS.accent)
                .fixedSize()
                .accessibilityLabel("Showing \(scope)'s swims")
        }
    }

    /// No history to describe at all. The refusal register — the page has
    /// nothing measured to show, so it draws no card furniture around a
    /// finding it does not have.
    private func emptyState(_ headline: String, _ detail: String) -> some View {
        FaultNote(headline: headline, detail: detail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    // MARK: - Swims it showed up in

    private func appearancesCard(_ summary: FaultHistory.Summary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Swims it showed up in")
            Text("Newest first · tap one to open its full results")
                .font(.caption)
                .foregroundStyle(DS.inkTertiary)
            // Lazy, like History's session list: a fault that has run
            // through two hundred swims is two hundred rows.
            LazyVStack(spacing: 8) {
                ForEach(summary.appearances.reversed()) { appearance in
                    // A swim whose stored result will not decode has nothing
                    // to open. It still gets a row — the appearance is real
                    // and counted — but not one that offers a tap and then
                    // does nothing, which is the failure v1.47.2 fixed for
                    // clips that would not play.
                    if appearance.resultIsReadable {
                        Button {
                            open(appearance)
                        } label: {
                            AppearanceRow(appearance: appearance, isOpenable: true)
                        }
                        .buttonStyle(ScaleButtonStyle())
                    } else {
                        AppearanceRow(appearance: appearance, isOpenable: false)
                    }
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    /// One O(n) scan over the session column, on a tap — never in layout.
    private func open(_ appearance: FaultHistory.Appearance) {
        guard let result = sessions.first(where: { $0.id == appearance.id })?.decoded()
        else { return }
        router.push(.results(result))
    }

    // MARK: - Drills

    /// The drill library's own read-out, not a second one: the rule, the
    /// sample gates and every word of copy come from `DrillEffect`, and the
    /// withheld-until-loaded guard from `DrillsView.readout`.
    private func drillsCard(_ readout: Readout) -> some View {
        let drills = DrillCatalog.drills(fixing: faultName)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "What to do about it")
            if let tip = entry?.tip {
                Text(tip)
                    .font(.footnote.weight(.medium))
                    .lineSpacing(3)
                    .foregroundStyle(DS.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(drills) { drill in
                DrillEffectSummaryRow(
                    drill: drill,
                    effect: DrillsView.readout(for: drill,
                                               events: practiceEvents,
                                               swims: readout.drillSwims,
                                               activeSwimmer: activeSwimmer))
            }
            Button {
                router.push(.drills(highlightIssue: faultName))
            } label: {
                HStack(spacing: 5) {
                    Text(drills.isEmpty ? "OPEN THE DRILL LIBRARY" : "FULL DRILL INSTRUCTIONS")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                        .tracking(1.2)
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(DS.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open drills that fix \(title)")
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - Load

    /// The one decode pass. See the type doc for why it lives here and what
    /// it is allowed to open.
    private func load() {
        var opened = 0
        let swims: [FaultHistory.Swim] = sessions.compactMap { session in
            let isLegacy = DrillEffect.isLegacyRow(issueNames: session.issueNames,
                                                   issueCount: session.issueCount)
            // Which swims may cost a disk read is `FaultHistory`'s rule, not
            // this view's — it is the page's performance contract, and a
            // contract stated only in a view body is one a test cannot hold.
            guard FaultHistory.needsResultBlob(issueNames: session.issueNames,
                                               issueCount: session.issueCount,
                                               fault: faultName) else {
                return Self.swim(session, faults: session.issueNames, strengths: [:])
            }
            opened += 1
            guard let issues = session.decoded()?.issues else {
                // A legacy row has no other record of what it contained, so
                // an unreadable one is DROPPED rather than counted
                // fault-free — the rule `DrillEffect` states, and reading it
                // as clean here would invent an improvement. A modern row
                // keeps its stored fault list and simply plots no point.
                return isLegacy
                    ? nil
                    : Self.swim(session, faults: session.issueNames, strengths: [:])
            }
            return Self.swim(session, faults: issues.map(\.name),
                             strengths: Dictionary(issues.map { ($0.name, $0.observedValue) },
                                                   uniquingKeysWith: { first, _ in first }))
        }
        readout = Readout(
            summary: FaultHistory.summary(of: faultName, in: swims,
                                          activeSwimmer: activeSwimmer),
            drillSwims: swims.map {
                DrillEffect.Swim(date: $0.date, issueNames: $0.faults, swimmer: $0.swimmer)
            })
        // One line per load, so "did the decode run once, and over how
        // little?" is an observable fact rather than a claim about the
        // code's shape. `.info` and not `.debug`: debug is not persisted by
        // default, and a diagnostic nobody can read afterwards is not one.
        // Matches the level the rest of `AppLog.storage` reports at.
        AppLog.storage.info("FaultDetail \(faultName, privacy: .public): opened \(opened, privacy: .public) of \(sessions.count, privacy: .public) stored results")
    }

    private static func swim(_ session: SwimSession,
                             faults: [String],
                             strengths: [String: Double]) -> FaultHistory.Swim {
        FaultHistory.Swim(id: session.id, date: session.analyzedAt, name: session.name,
                          score: session.score, grade: session.grade,
                          swimmer: session.swimmer, faults: faults, strengths: strengths)
    }
}
