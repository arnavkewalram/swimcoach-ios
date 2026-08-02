import CoreGraphics
import ImageIO

/// Rotation-metadata math for the video pipeline. iPhone recordings store
/// sensor-native frames plus a `preferredTransform`; every consumer must
/// agree on one space. Convention after this fix: **keypoints live in
/// display (oriented) space** — Vision is told the orientation, the
/// overlay maps against the display size, and the exporter converts
/// display points back into raw frame pixels. All pure — unit-tested.
enum VideoTransform {

    /// How Vision should orient raw frames to see upright content.
    /// Apple's canonical mapping from a track's preferredTransform.
    static func orientation(for t: CGAffineTransform) -> CGImagePropertyOrientation {
        if t.a == 0 && t.b == 1 && t.c == -1 && t.d == 0 { return .right }   // portrait
        if t.a == 0 && t.b == -1 && t.c == 1 && t.d == 0 { return .left }    // portrait upside-down
        if t.a == -1 && t.b == 0 && t.c == 0 && t.d == -1 { return .down }   // landscape flipped
        return .up
    }

    /// The size the video actually displays at (natural size pushed
    /// through the transform — width/height swap for 90° rotations).
    static func displaySize(natural: CGSize, transform t: CGAffineTransform) -> CGSize {
        let r = CGRect(origin: .zero, size: natural).applying(t)
        return CGSize(width: abs(r.width), height: abs(r.height))
    }

    /// Map a Vision-normalized point in DISPLAY space (bottom-left origin,
    /// as Vision reports when given the orientation) to a top-left pixel
    /// position in the RAW frame — where the exporter draws.
    static func rawPixelPoint(visionDisplayPoint p: CGPoint,
                              natural: CGSize,
                              transform t: CGAffineTransform) -> CGPoint {
        let dispRect = CGRect(origin: .zero, size: natural).applying(t)
        // Vision bottom-left normalized → top-left display pixels
        let displayPixel = CGPoint(x: p.x * dispRect.width,
                                   y: (1 - p.y) * dispRect.height)
        // Undo the transform's translation, then invert the rotation
        let absolute = CGPoint(x: displayPixel.x + dispRect.minX,
                               y: displayPixel.y + dispRect.minY)
        return absolute.applying(t.inverted())
    }
}
