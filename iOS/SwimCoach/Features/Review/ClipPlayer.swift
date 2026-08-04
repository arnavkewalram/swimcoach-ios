import SwiftUI
import AVFoundation
import Combine

/// Bare `AVPlayerLayer` surface — no AVKit transport chrome.
///
/// Results uses `VideoPlayer`, whose system HUD is the right call there
/// (share, AirPlay, full screen). Review is a decision screen: it wants a
/// clean frame and a scrubber drawn in the meet-sheet language, so it drives
/// the layer directly and supplies its own transport below the band.
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
}

/// Transport for the review clip: a play/pause mark, a lane-rule track with a
/// lane-blue fill and a playhead marker, and monospaced time codes. Dragging
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

    private var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, currentTime / duration))
    }

    var body: some View {
        HStack(spacing: 14) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(DS.accent.opacity(0.45), lineWidth: 1))
                    .contentShape(Circle())
            }
            .accessibilityLabel(isPlaying ? "Pause clip" : "Play clip")

            track

            Text("\(ClipTime.code(currentTime)) / \(ClipTime.code(duration))")
                .font(.custom(GroteskWeight.medium.postScriptName, size: 11))
                .monospacedDigit()
                .tracking(0.6)
                .foregroundStyle(DS.inkTertiary)
                .fixedSize()
                .accessibilityHidden(true)
        }
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

    // MARK: - Track

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
                    .onChanged { value in
                        isScrubbing = true
                        seek(toFraction: value.location.x / max(width, 1))
                    }
                    .onEnded { value in
                        seek(toFraction: value.location.x / max(width, 1))
                        isScrubbing = false
                    }
            )
        }
        .frame(height: 34)
        .accessibilityElement()
        .accessibilityLabel("Clip position")
        .accessibilityValue("\(ClipTime.code(currentTime)) of \(ClipTime.code(duration))")
        .accessibilityAdjustableAction { direction in
            let step = 1.0 / max(duration, 1)
            seek(toFraction: fraction + (direction == .increment ? step : -step))
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
