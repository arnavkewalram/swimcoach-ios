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

    @State private var player: AVPlayer?
    @State private var duration: Double = 0

    /// The framing rules the model actually depends on — the same advice the
    /// camera cycles through, restated as a checklist now that there is
    /// something to check it against.
    private let framingChecks = [
        "Side-on, camera at water level",
        "Full body above the waterline",
        "One lap at a normal pace",
    ]

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

    /// A fixed screening band: `resizeAspect` letterboxes portrait and
    /// landscape takes alike, so the page rhythm never depends on how the
    /// phone was held.
    private var clipBand: some View {
        ZStack {
            Color.black
            if let player {
                ClipPlayerSurface(player: player)
            } else {
                ProgressView().tint(.white)
            }
        }
        // Sized so the whole page — band, transport, checklist, actions —
        // rests above the fold at the default type size instead of leaving
        // the checklist card cut off by the action bar.
        .frame(height: 224)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.border, lineWidth: 1))
        .accessibilityLabel("Preview of the clip you just recorded")
    }

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
            SectionHeader(title: "What the model needs")

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(framingChecks.enumerated()), id: \.offset) { index, check in
                    HStack(spacing: 12) {
                        Text(String(format: "%02d", index + 1))
                            .font(.grotesk(12, .medium))
                            .foregroundStyle(DS.accent)
                            .frame(width: 22, alignment: .leading)
                            .accessibilityHidden(true)
                        Text(check)
                            .font(.system(size: 14))
                            .foregroundStyle(DS.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    if index < framingChecks.count - 1 {
                        Rectangle().fill(DS.border).frame(height: 1)
                    }
                }
            }
            .glassCard()
        }
    }

    // MARK: - Actions

    private var actionBar: some View {
        VStack(spacing: 10) {
            LaneRule()
                .padding(.bottom, 4)

            Button {
                Haptics.tap()
                // replaceTop, not push: Back out of Analyzing must land on the
                // camera, not on a review screen whose clip analysis already
                // owns.
                router.replaceTop(with: .analyzing(clip))
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
                router.replaceTop(with: .camera)
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
