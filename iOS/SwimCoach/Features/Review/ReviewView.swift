import SwiftUI
import AVFoundation

/// The keep-or-retake step between the camera and analysis.
///
/// Recording used to hand straight off to `AnalyzingView`, so a bad take was
/// only discovered after a minute of inference — and the capture itself lived
/// in a temp directory that nothing ever promoted, making a discarded or
/// failed clip unrecoverable. The clip now arrives here already adopted into
/// `SessionVideoStore` (see `PendingClip`): "Use this clip" hands the same id
/// to analysis so the stored file and the saved session agree on a name, and
/// "Retake" discards it explicitly instead of leaking it.
struct ReviewView: View {
    let clip: PendingClip

    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var player: AVPlayer?
    @State private var duration: Double = 0

    /// Lane-number column width. Scaled, because "02" set in Space Grotesk
    /// outgrows a hard 22pt column at accessibility sizes and truncates to a
    /// bare "0" — the ordinals stop being ordinals exactly when they are
    /// needed most.
    @ScaledMetric(relativeTo: .footnote) private var laneColumn: CGFloat = 22

    /// Checklist body size. This was a flat `.system(size: 14)`, which does
    /// not scale at all — so at accessibility sizes the decorative lane
    /// numbers beside it (Space Grotesk, which does scale) grew past the
    /// instructions they index. `Font.system` has no `relativeTo:` overload,
    /// so the scaling comes from the metric.
    @ScaledMetric(relativeTo: .subheadline) private var checkSize: CGFloat = 14

    /// Card gutters. Named because the lane rule is positioned from them.
    private static let rowInset: CGFloat = 16
    private static let laneGap: CGFloat = 12

    /// The framing rules the model actually depends on — the same advice the
    /// camera cycles through, restated as a checklist now that there is
    /// something to check it against.
    private let framingChecks = [
        "Side-on, camera at water level",
        "Full body above the waterline",
        "One lap at a normal pace",
    ]

    private let checklistTitle = "What the model needs"

    var body: some View {
        ZStack {
            DS.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        masthead
                        clipBand
                        transport
                        checklist
                        Spacer(minLength: 16)
                    }
                    .padding(.horizontal, 24)
                }
                actionBar
            }
        }
        .navigationBarHidden(true)
        .task { await loadClip() }
        .onDisappear { player?.pause() }
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("REVIEW")
                    .font(.sectionLabel)
                    .tracking(2.0)
                    .foregroundStyle(DS.accent)
                Spacer()
                Text(duration > 0 ? "TAKE · \(ClipTime.code(duration))" : "TAKE")
                    .font(.sectionLabel)
                    .tracking(1.2)
                    .monospacedDigit()
                    .foregroundStyle(DS.inkTertiary)
            }
            .padding(.top, 14)

            Text("Check the\nframing")
                .font(.grotesk(30, .bold))
                .foregroundStyle(DS.ink)
                .padding(.top, 10)
                .padding(.bottom, 16)

            LaneRule()
                .padding(.bottom, 18)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(duration > 0
            ? "Review your take, \(ClipTime.code(duration)) long. Check the framing."
            : "Review your take. Check the framing.")
    }

    // MARK: - Clip

    /// A screening band: `resizeAspect` letterboxes portrait and landscape
    /// takes alike, so the page rhythm never depends on how the phone was
    /// held.
    private var clipBand: some View {
        ZStack {
            Color.black
            if let player {
                ClipPlayerSurface(player: player)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(height: Self.clipBandHeight(for: typeSize))
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.border, lineWidth: 1))
        // Neither `Color.black` nor the `UIViewRepresentable` is an
        // accessibility element, so it looks like the bare
        // `.accessibilityLabel` this used to carry had nothing to attach to.
        // It did: `SmokeUITests.testReviewClipBandIsReachableByVoiceOver`
        // passes against the old code too — SwiftUI synthesises an element
        // for a labelled view with no accessible children. The explicit
        // promotion stays anyway, matching `ClipScrubber`: it states the
        // intent, and it keeps the band a single element if anything
        // accessible is ever added inside the ZStack.
        .accessibilityElement()
        .accessibilityLabel("Preview of the clip you just recorded")
    }

    /// The band is this page's shock absorber.
    ///
    /// It used to be a hard 224pt, sized so the whole page rested above the
    /// fold *at the default type size*; at accessibility sizes the grown
    /// masthead pushed the checklist under the action bar, clipping item 02
    /// mid-glyph and hiding 03 entirely with no scroll cue. Everything else
    /// on the screen is text that must grow, and the video is the least
    /// information-dense element here — so the video is what gives way.
    ///
    /// The accessibility step is set for a 844pt screen (iPhone 14/15/16
    /// class), not for the 874pt Pro it was first checked on: at 124pt the
    /// sheet still fits the Pro but item 03 was sliced on every mainstream
    /// phone. Shorter bodies than that (SE, mini) cannot hold this much text
    /// at any band height and correctly fall back to scrolling.
    static func clipBandHeight(for size: DynamicTypeSize) -> CGFloat {
        if size.isAccessibilitySize { return 108 }
        if size >= .xLarge { return 180 }
        return 224
    }

    /// Row gutters shrink once the type is doing the spacing work itself.
    /// The other half of the 844pt budget above.
    private var rowPadding: CGFloat { typeSize.isAccessibilitySize ? 10 : 13 }

    @ViewBuilder
    private var transport: some View {
        if let player {
            ClipScrubber(player: player, duration: duration)
                .padding(.top, 4)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Checklist

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 10) {
            checklistHeader

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(framingChecks.enumerated()), id: \.offset) { index, check in
                    HStack(alignment: .firstTextBaseline, spacing: Self.laneGap) {
                        Text(String(format: "%02d", index + 1))
                            .font(.grotesk(12, .medium))
                            .foregroundStyle(DS.accent)
                            .frame(width: laneColumn, alignment: .leading)
                            .accessibilityHidden(true)
                        Text(check)
                            .font(.system(size: checkSize))
                            .foregroundStyle(DS.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Self.rowInset)
                    .padding(.vertical, rowPadding)
                    if index < framingChecks.count - 1 {
                        Rectangle().fill(DS.border).frame(height: 1)
                    }
                }
            }
            .overlay(alignment: .leading) { laneRule }
            .glassCard()
        }
    }

    /// `SectionHeader` sets its lane rule beside the title, so at
    /// accessibility sizes "WHAT THE / MODEL NEEDS" wraps and the rule
    /// collapses to a dash floating at mid-height. `SectionHeader.singleLine`
    /// exists for exactly this (see DesignSystem.swift) — Review just never
    /// used it. The stacked branch is spelled out here rather than reusing
    /// the shared header because the shared one always puts the rule beside
    /// the label; below it, the rule reads as a full-width underscore again.
    private var checklistHeader: some View {
        ViewThatFits(in: .horizontal) {
            SectionHeader(title: checklistTitle, singleLine: true)
            VStack(alignment: .leading, spacing: 6) {
                Text(checklistTitle.uppercased())
                    .font(.sectionLabel)
                    .tracking(1.6)
                    .foregroundStyle(DS.inkSecondary)
                LaneRule()
            }
        }
    }

    /// The column rule that turns three numbered lines into a heat sheet:
    /// lane numbers ruled off from the names, the way the paper original
    /// does it. Drawn as one overlay rather than per row so it runs unbroken
    /// through the row hairlines and gets mitred by the card's corner
    /// radius; it tracks `laneColumn`, so it stays in the gutter at every
    /// type size.
    private var laneRule: some View {
        Rectangle()
            .fill(DS.border)
            .frame(width: 1)
            .padding(.leading, Self.rowInset + laneColumn + Self.laneGap / 2)
            .accessibilityHidden(true)
    }

    // MARK: - Actions

    private var actionBar: some View {
        VStack(spacing: 10) {
            LaneRule()
                .padding(.bottom, 4)

            Button {
                Haptics.tap()
                Self.routeToAnalysis(router, clip: clip)
            } label: {
                PrimaryButtonLabel(title: "Use this clip")
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Analyze this clip")

            Button {
                Haptics.tap()
                player?.pause()
                // The take is being rejected — drop the adopted file now
                // rather than leaving it for the next launch's sweep.
                SessionVideoStore.discard(clip)
                Self.routeToRetake(router)
            } label: {
                SecondaryButtonLabel(title: "Retake", icon: "arrow.counterclockwise")
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Discard this clip and record again")
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(DS.background)
    }

    // MARK: - Navigation
    //
    // Both exits leave the stack instead of pushing onto it, and both are
    // factored out of the buttons so `AppRouterTests` can pin the resulting
    // stack shape — `NavigationPath` is type-erased, so a wrong shape is
    // otherwise invisible until it shows up as a duplicated screen.

    /// Hand the clip to analysis. `replaceTop`, not `push`: Back out of
    /// Analyzing must land on the camera, not on a review screen whose clip
    /// analysis already owns.
    ///
    /// Safe here — the entry below Review is `.camera` (recording) or nothing
    /// (the DEBUG `-demoReview` route), never `.analyzing`, so this swap
    /// cannot duplicate the destination it appends.
    static func routeToAnalysis(_ router: AppRouter, clip: PendingClip) {
        router.replaceTop(with: .analyzing(clip))
    }

    /// Go back to the camera for another take.
    ///
    /// popToRoot + push, never `replaceTop`: `CameraView` pushes `.review`
    /// when recording stops, so the live stack is `[camera, review]` and
    /// `replaceTop(with: .camera)` would drop `review` and append a *second*
    /// camera — with every further record→retake cycle stacking another.
    /// This is also correct from the DEBUG `-demoReview` route, where the
    /// stack is just `[review]` and Home is already the root. Same reasoning
    /// as `AnalyzingView`'s `.recordAgain`.
    static func routeToRetake(_ router: AppRouter) {
        router.popToRoot()
        router.push(.camera)
    }

    // MARK: - Loading

    private func loadClip() async {
        guard player == nil else { return }
        let asset = AVURLAsset(url: clip.url)
        if let seconds = try? await asset.load(.duration).seconds, seconds.isFinite {
            duration = seconds
        }
        let item = AVPlayerItem(asset: asset)
        let created = AVPlayer(playerItem: item)
        created.isMuted = true
        player = created
        created.play()
    }
}
