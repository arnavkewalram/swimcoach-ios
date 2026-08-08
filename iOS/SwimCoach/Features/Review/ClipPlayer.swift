import SwiftUI
import AVFoundation
import Combine

/// Bare `AVPlayerLayer` surface — no AVKit transport chrome.
///
/// Results uses `VideoPlayer`, whose system HUD is the right call there
/// (share, AirPlay, full screen). Review is a decision screen: it wants a
/// clean frame and a scrubber drawn in the meet-sheet language, so it drives
/// the layer directly and supplies its own transport below the band. Compare
/// needs the same bare surface twice — a system HUD per pane would put two
/// competing transports on one screen.
struct ClipPlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }

    final class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// Clip time codes — `0:07`, matching the meet-sheet's monospaced data marks.
enum ClipTime {
    static func code(_ seconds: Double) -> String {
        let total = Int(seconds.isFinite ? max(0, seconds.rounded()) : 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// The paired form under a pane and beside a transport: `0:07 / 0:20`.
    static func code(_ seconds: Double, of duration: Double) -> String {
        "\(code(seconds)) / \(code(duration))"
    }
}

// MARK: - Transport marks

/// The transport itself — a play/pause mark, a lane-rule track with a
/// lane-blue fill and a playhead marker, and a monospaced time code — with no
/// opinion about what is playing.
///
/// Review binds it to one `AVPlayer` (see `ClipScrubber`); Compare binds it to
/// a synced pair. Everything here is a function of `position`, so a driver of
/// any shape can hold up the same marks rather than a second transport being
/// drawn in a different dialect.
struct ClipTransportBar: View {
    /// 0…1 through whatever is being played.
    let position: Double
    let isPlaying: Bool
    /// Right-hand code, already formatted (`0:07 / 0:20`).
    let timeCode: String
    /// Spoken value for the track, e.g. "0:07 of 0:20".
    let spokenPosition: String
    /// How far one VoiceOver increment moves, as a fraction of the whole.
    let adjustStep: Double
    let onToggle: () -> Void
    /// Called continuously while the finger is down — the driver holds the
    /// playhead against its own clock for the duration.
    let onScrub: (Double) -> Void
    /// Called once on release, and by VoiceOver's adjustable action.
    let onScrubEnd: (Double) -> Void

    /// Both marks here are deliberately small — a play mark and a lane rule,
    /// not a knob and a slider. The drawn marks stay small; the *targets*
    /// around them are the HIG minimum.
    static let hitTarget: CGFloat = 44

    /// The drawn ring grows with type, then stops at the target it sits
    /// inside — past that it would only crowd the track.
    @ScaledMetric(relativeTo: .footnote) private var ringDiameter: CGFloat = 34
    private var ring: CGFloat { min(ringDiameter, Self.hitTarget) }
    /// Glyph derived from the ring so the mark keeps its proportions at every
    /// size (13pt inside 34pt at the default).
    private var glyph: CGFloat { (ring * 13.0 / 34.0).rounded() }

    private var fraction: Double {
        guard position.isFinite else { return 0 }
        return min(1, max(0, position))
    }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: glyph, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .frame(width: ring, height: ring)
                    .overlay(Circle().stroke(DS.accent.opacity(0.45), lineWidth: 1))
                    .frame(width: Self.hitTarget, height: Self.hitTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(isPlaying ? "Pause clip" : "Play clip")

            track

            Text(timeCode)
                .font(.custom(GroteskWeight.medium.postScriptName,
                              size: 11, relativeTo: .caption2))
                .monospacedDigit()
                .tracking(0.6)
                .foregroundStyle(DS.inkTertiary)
                .fixedSize()
                .accessibilityHidden(true)
        }
    }

    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(DS.border)
                    .frame(height: 3)
                Rectangle()
                    .fill(DS.accent)
                    .frame(width: width * fraction, height: 3)
                // Playhead: a lane marker, not a knob.
                Rectangle()
                    .fill(DS.accent)
                    .frame(width: 2, height: 16)
                    .offset(x: max(0, min(width - 2, width * fraction - 1)))
            }
            .frame(height: geo.size.height, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onScrub($0.location.x / max(width, 1)) }
                    .onEnded { onScrubEnd($0.location.x / max(width, 1)) }
            )
        }
        // The drawn track is a 3pt rule with a 16pt playhead, centred inside
        // a full-height drag target.
        .frame(height: Self.hitTarget)
        .accessibilityElement()
        .accessibilityLabel("Clip position")
        .accessibilityValue(spokenPosition)
        .accessibilityAdjustableAction { direction in
            onScrubEnd(fraction + (direction == .increment ? adjustStep : -adjustStep))
        }
    }
}

// MARK: - Single-clip transport

/// `ClipTransportBar` bound to one player: Review's transport. Dragging
/// anywhere on the track seeks.
struct ClipScrubber: View {
    let player: AVPlayer
    /// Clip length in seconds. Zero until the asset loads — the track then
    /// renders empty rather than dividing by zero.
    let duration: Double

    @State private var currentTime: Double = 0
    @State private var isPlaying = true
    /// While dragging, the periodic observer must not fight the finger.
    @State private var isScrubbing = false
    @State private var timeObserver: Any?

    /// Kept here because callers and `ReviewLayoutTests` name the target
    /// through the scrubber; the marks themselves live on the bar.
    static let hitTarget: CGFloat = ClipTransportBar.hitTarget

    private var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, currentTime / duration))
    }

    var body: some View {
        ClipTransportBar(
            position: fraction,
            isPlaying: isPlaying,
            timeCode: ClipTime.code(currentTime, of: duration),
            spokenPosition: "\(ClipTime.code(currentTime)) of \(ClipTime.code(duration))",
            adjustStep: 1.0 / max(duration, 1),
            onToggle: togglePlayback,
            onScrub: { f in
                isScrubbing = true
                seek(toFraction: f)
            },
            onScrubEnd: { f in
                seek(toFraction: f)
                isScrubbing = false
            }
        )
        .onAppear(perform: startObserving)
        .onDisappear(perform: stopObserving)
        // Loop: a review clip is a few seconds long and the user is judging
        // framing, so it replays instead of freezing on the last frame.
        .onReceive(NotificationCenter.default.publisher(
            for: AVPlayerItem.didPlayToEndTimeNotification)) { _ in
            player.seek(to: .zero)
            if isPlaying { player.play() }
        }
    }

    // MARK: - Playback

    private func togglePlayback() {
        Haptics.tap()
        isPlaying.toggle()
        if isPlaying { player.play() } else { player.pause() }
    }

    private func seek(toFraction f: Double) {
        guard duration > 0 else { return }
        let clamped = min(1, max(0, f))
        currentTime = clamped * duration
        player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func startObserving() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 20), queue: .main
        ) { time in
            guard !isScrubbing else { return }
            currentTime = CMTimeGetSeconds(time)
        }
    }

    private func stopObserving() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }
}
