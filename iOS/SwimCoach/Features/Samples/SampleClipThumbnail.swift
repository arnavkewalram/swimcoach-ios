import SwiftUI
import AVFoundation

/// A still lifted out of a bundled sample clip.
///
/// Generated from the asset rather than shipped as a second image: four PNGs
/// would be four more files to keep in step with the clips they claim to
/// show, and the first one to drift would be a thumbnail advertising footage
/// the row does not play.
///
/// The box is laid out at its final size on first paint and the frame
/// crossfades in behind it, so the list is exactly as tall before the stills
/// arrive as after — no row ever reflows under the user's thumb.
struct SampleClipThumbnail: View {
    let clip: SampleClip

    /// Every sample is 16:9. The width tracks `.footnote`, because the still
    /// sits beside the row's supporting text and should grow with it, and it
    /// is capped because a thumbnail is a fixed mark next to a row — past
    /// this it stops illustrating the row and starts being the row.
    static let baseWidth: CGFloat = 92
    static let maxWidth: CGFloat = 128
    static let aspectRatio: CGFloat = 16.0 / 9.0
    private static let cornerRadius: CGFloat = 6

    @ScaledMetric(relativeTo: .footnote)
    private var scaledWidth: CGFloat = SampleClipThumbnail.baseWidth
    @State private var frame: CGImage?

    private var width: CGFloat { min(scaledWidth, Self.maxWidth) }
    private var height: CGFloat { (width / Self.aspectRatio).rounded() }

    var body: some View {
        ZStack {
            // Reserved ground — drawn before, during and after the load, so
            // the row's geometry never depends on whether the still arrived.
            Rectangle().fill(DS.surface2)
            if let frame {
                Image(decorative: frame, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius)
            .stroke(DS.border, lineWidth: 1))
        // The row's own text names the vantage and describes the footage;
        // VoiceOver reading "image" here would only add noise.
        .accessibilityHidden(true)
        .task(id: clip.id) { await loadFrame() }
    }

    /// A frame from the middle of the swim.
    ///
    /// Proportional rather than a fixed offset, and deliberately not frame
    /// zero. These clips are handheld: they open with the swimmer at distance,
    /// half out of shot or not yet in it, and a first-second still gave two of
    /// the four rows a thumbnail of empty water. Taking the point at
    /// `midSwimFraction` puts the swimmer in frame in all four, and keeps
    /// doing so for a fifth clip of some other length.
    private static let midSwimFraction = 0.6

    private func loadFrame() async {
        guard frame == nil, let url = clip.bundleURL() else { return }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // Enough to fill the capped box on a 3× screen, and no more — the
        // full 854×480 frame is four times the pixels this ever draws.
        generator.maximumSize = CGSize(width: Self.maxWidth * 3,
                                       height: (Self.maxWidth / Self.aspectRatio) * 3)
        // Nearest keyframe is fine and much cheaper — nothing here depends on
        // landing on one exact frame.
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        // An unreadable duration falls back to a second in rather than to
        // zero: a still of the opening frame is the case this avoids.
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let seconds = duration > 0 ? duration * Self.midSwimFraction : 1
        let at = CMTime(seconds: seconds, preferredTimescale: 600)
        // A still that will not decode is not worth a failure state: the
        // reserved ground already reads as a clip box, and the row's text —
        // which is what actually describes the footage — is unaffected.
        guard let image = try? await generator.image(at: at).image else {
            AppLog.storage.info("No thumbnail frame for \(clip.fileName)")
            return
        }
        withAnimation(.easeIn(duration: 0.18)) { frame = image }
    }
}
