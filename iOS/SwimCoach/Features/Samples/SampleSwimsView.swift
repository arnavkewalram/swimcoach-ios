import SwiftUI

/// "Try a sample swim" — four real clips the app can analyze for a swimmer
/// who has not filmed anything yet.
///
/// ── The two things this screen has to keep straight ─────────────────────
///
/// **The analysis is real, and the screen says so.** These clips go through
/// the same `PoseAnalyzer` → `FeatureExtractor` → `SwimTCNRunner` →
/// `FeedbackEngine` path a filmed lap does. The score that comes out is what
/// SwimTCN actually found in those frames on this iPhone. Nothing here
/// disclaims it as a mock-up, because it is not one.
///
/// **The swim is not the user's, and the screen says that too.** So no row
/// wears a `VerdictChip` — the app has not measured anything at list time,
/// and the chip is the app's word for "we measured this" — and no result
/// from here is written to the store. Both facts are stated before the tap,
/// in the register the app uses for facts, not buried in a footnote after.
///
/// Presented as a sheet from Home rather than pushed, so that the analysis
/// it launches lands on Home's own navigation stack: the sheet closes, the
/// stack pushes Analyzing, and Back from Results goes home the way it does
/// for a filmed swim.
struct SampleSwimsView: View {
    /// Called with the chosen clip. The caller closes the sheet and pushes
    /// analysis — this screen deliberately does not own the router, so the
    /// run it starts belongs to the stack behind it.
    let onSelect: (SampleClip) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var clips: [SampleClip] { SampleClipCatalog.all }
    private var credit: SampleClipAttribution { SampleClipCatalog.attribution }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        masthead
                        terms.padding(.bottom, 26)
                        clipList.padding(.bottom, 26)
                        footageCredit
                        Spacer(minLength: 28)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .navigationTitle("Sample swims")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Sample swims")
                        .font(.grotesk(17, .medium))
                        .foregroundStyle(DS.ink)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DS.accent)
                }
            }
            .toolbarBackground(DS.background, for: .navigationBar)
        }
        .presentationBackground(DS.background)
        .accessibilityIdentifier("sampleSwimsScreen")
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SAMPLE SWIMS")
                .font(.sectionLabel)
                .tracking(2.0)
                .foregroundStyle(DS.accent)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Text("Watch it run on\nsomebody else's swim")
                .font(.grotesk(28, .bold))
                .foregroundStyle(DS.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            LaneRule()
                .padding(.bottom, 16)

            Text("\(clips.count) real clips from an open-licensed swimming lesson. Tap one and SwimCoach analyzes it the same way it analyzes a swim you film.")
                .font(.footnote)
                .lineSpacing(4)
                .foregroundStyle(DS.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - The terms of the demonstration

    /// Both halves of the honest claim, given equal weight and stated before
    /// the user taps anything. They are a pair on purpose: either one alone
    /// misleads. "Real analysis" without "not saved" implies these swims join
    /// the user's training; "not saved" without "real analysis" reads as a
    /// confession that the numbers are fake, which would be its own lie.
    private var terms: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "What you get")

            VStack(alignment: .leading, spacing: 0) {
                TermRow(
                    heading: "Real numbers",
                    detail: "SwimTCN runs on this iPhone, on these frames. The score and the faults are what the model actually found.")
                Rectangle().fill(DS.border).frame(height: 1)
                TermRow(
                    heading: "Not your swim, not saved",
                    detail: "These are somebody else's laps, so the result is not written to your history. It cannot move your trends, your streak, your weekly goal or your drill statistics.")
            }
            .glassCard()
        }
    }

    // MARK: - Clips

    private var clipList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Clips")

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                    // A clip that did not make it into the bundle is a real
                    // shipping failure (see SampleClipCatalogTests). It is
                    // shown inert rather than hidden, because a row that
                    // silently vanishes is a bug nobody reports.
                    let isPlayable = clip.bundleURL() != nil
                    Button {
                        onSelect(clip)
                    } label: {
                        SampleClipRow(clip: clip,
                                      index: index,
                                      isPlayable: isPlayable,
                                      isStacked: dynamicTypeSize.isAccessibilitySize)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(!isPlayable)

                    if index < clips.count - 1 {
                        Rectangle().fill(DS.border).frame(height: 1)
                    }
                }
            }
            .glassCard()
        }
    }

    // MARK: - Attribution

    /// A licence condition, not a courtesy — CC BY 3.0 §4(c) requires the
    /// work, the author and the licence to travel with the footage. Set in
    /// the same register About uses for the SIL OFL type credit, and placed
    /// on the screen that plays the clips rather than three taps away, so
    /// the credit is visible to anyone who sees the thing it is crediting.
    private var footageCredit: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Footage")

            Text(credit.creditLine)
                .font(.footnote)
                .lineSpacing(4)
                .foregroundStyle(DS.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Link(destination: credit.licenseURL) {
                HStack(spacing: 6) {
                    Text("VIEW \(credit.licenseShortName) LICENCE")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                        .tracking(1.2)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(DS.accent)
                // The pill stays compact; the frame lifts the tap target to
                // the 44pt HIG minimum before contentShape claims it.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("View the \(credit.licenseName) licence")
            .accessibilityAddTraits(.isLink)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Term row

/// One half of the deal, as a heading plus its consequence. Grotesk carries
/// the heading (the data register), SF the sentence — the same split
/// `AnalyzingView`'s requirement rows use.
private struct TermRow: View {
    let heading: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // A lane tick, not a checkmark: nothing here has been verified
            // for the user, it is simply the arrangement.
            Rectangle()
                .fill(DS.accent)
                .frame(width: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(heading)
                    .font(.grotesk(14, .medium))
                    .foregroundStyle(DS.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.footnote)
                    .lineSpacing(3)
                    .foregroundStyle(DS.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Clip row

/// One sample, described by where the camera was and what is in shot —
/// never by what the model will say about it. See `SampleClipCatalog`.
private struct SampleClipRow: View {
    let clip: SampleClip
    let index: Int
    let isPlayable: Bool
    /// At accessibility text sizes the still moves above the copy instead of
    /// beside it: a 128pt thumbnail plus a wrapping paragraph in one row
    /// leaves the paragraph about four characters wide.
    let isStacked: Bool

    private var lane: String { String(format: "%02d", index + 1) }

    var body: some View {
        Group {
            if isStacked {
                VStack(alignment: .leading, spacing: 12) {
                    SampleClipThumbnail(clip: clip)
                    copy
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    SampleClipThumbnail(clip: clip)
                    copy
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isPlayable ? 1 : 0.5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isPlayable ? .isButton : [])
        .accessibilityIdentifier("sampleClipRow-\(clip.resourceName)")
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(lane)
                    .font(.grotesk(11, .medium))
                    .foregroundStyle(DS.accent)
                Text(clip.vantage.uppercased())
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                    .tracking(1.2)
                    .foregroundStyle(DS.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            Text(clip.title)
                .font(.grotesk(15, .medium))
                .foregroundStyle(DS.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(clip.footage)
                .font(.footnote)
                .lineSpacing(3)
                .foregroundStyle(DS.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if isPlayable {
                HStack(spacing: 5) {
                    Text("ANALYZE THIS CLIP")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                        .tracking(1.2)
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(DS.accent)
                .padding(.top, 2)
            } else {
                // Not a chip: the app has no finding here, only an absence.
                Text("NOT INSTALLED")
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                    .tracking(1.2)
                    .foregroundStyle(DS.severityModerate)
                    .padding(.top, 2)
            }
        }
    }

    private var accessibilityLabel: String {
        let head = "Clip \(index + 1), \(clip.title). \(clip.vantage). \(clip.footage)"
        return isPlayable
            ? "\(head) Analyzes this clip."
            : "\(head) This clip did not ship with the app and cannot be analyzed."
    }
}
