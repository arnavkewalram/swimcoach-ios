import SwiftUI
import AVKit

/// Draws the detected pose skeleton over the session video, synced to
/// playback time. Sits in a ZStack directly above the VideoPlayer.
struct SkeletonOverlayView: View {
    let player: AVPlayer
    let frames: [KeypointFrame]
    /// Natural pixel size of the video, used to compute the letterboxed
    /// content rect inside the player view.
    let videoSize: CGSize

    @State private var currentTime: Double = 0
    @State private var timeObserver: Any?

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard let frame = frames.nearest(to: currentTime) else { return }
                let rect = videoContentRect(in: size)

                func viewPoint(_ p: (x: CGFloat, y: CGFloat)) -> CGPoint {
                    // Vision coords: normalized, origin bottom-left → flip y.
                    CGPoint(x: rect.minX + p.x * rect.width,
                            y: rect.minY + (1 - p.y) * rect.height)
                }

                // Limbs
                var lines = Path()
                for (a, b) in KeypointFrame.limbs {
                    guard let pa = frame.point(a), let pb = frame.point(b) else { continue }
                    lines.move(to: viewPoint(pa))
                    lines.addLine(to: viewPoint(pb))
                }
                context.stroke(lines, with: .color(DS.accent.opacity(0.85)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round))

                // Joints
                for j in 0..<KeypointFrame.jointCount {
                    guard let p = frame.point(j) else { continue }
                    let c = viewPoint(p)
                    let dot = CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)
                    context.fill(Path(ellipseIn: dot), with: .color(.white))
                    context.stroke(Path(ellipseIn: dot), with: .color(DS.accent), lineWidth: 1.5)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(value: 1, timescale: 15), queue: .main
            ) { time in
                currentTime = CMTimeGetSeconds(time)
            }
        }
        .onDisappear {
            if let observer = timeObserver {
                player.removeTimeObserver(observer)
                timeObserver = nil
            }
        }
    }

    /// The rect the video content actually occupies inside the player view
    /// (AVPlayerViewController letterboxes with resizeAspect).
    private func videoContentRect(in size: CGSize) -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        return AVMakeRect(aspectRatio: videoSize,
                          insideRect: CGRect(origin: .zero, size: size))
    }
}
