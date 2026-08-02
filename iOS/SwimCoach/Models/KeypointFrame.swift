import Foundation
import Vision

/// One sampled frame of pose keypoints, stored with each session so playback
/// can draw the detected skeleton over the video.
///
/// Coordinates are Vision-native: normalized [0,1], origin bottom-left
/// (y up). Renderers flip y when drawing into a top-left view space.
/// Joint order matches `FeatureExtractor.joints` (13 joints); a joint the
/// detector didn't see is (0, 0, 0).
struct KeypointFrame: Hashable, Codable, Sendable {
    /// Source-video presentation time in seconds.
    let t: Double
    /// Flattened [x, y, confidence] per joint — 39 values.
    let joints: [Float]

    static let jointCount = 13
    static let minConfidence: Float = 0.1

    /// Skeleton limb connections as (fromJointIndex, toJointIndex) pairs,
    /// indices into `FeatureExtractor.joints` order.
    static let limbs: [(Int, Int)] = [
        (1, 2),            // shoulders
        (1, 3), (3, 5),    // left arm
        (2, 4), (4, 6),    // right arm
        (1, 7), (2, 8),    // torso
        (7, 8),            // hips
        (7, 9), (9, 11),   // left leg
        (8, 10), (10, 12), // right leg
    ]

    func point(_ jointIndex: Int) -> (x: CGFloat, y: CGFloat)? {
        let base = jointIndex * 3
        guard base + 2 < joints.count, joints[base + 2] > Self.minConfidence else { return nil }
        return (CGFloat(joints[base]), CGFloat(joints[base + 1]))
    }

    static func frames(from timed: [PoseAnalyzer.TimedObservation]) -> [KeypointFrame] {
        timed.map { item in
            var values = [Float](repeating: 0, count: jointCount * 3)
            for (j, joint) in FeatureExtractor.joints.enumerated() {
                if let pt = try? item.observation.recognizedPoint(joint),
                   pt.confidence > minConfidence {
                    values[j * 3]     = Float(pt.location.x)
                    values[j * 3 + 1] = Float(pt.location.y)
                    values[j * 3 + 2] = Float(pt.confidence)
                }
            }
            return KeypointFrame(t: item.seconds, joints: values)
        }
    }
}

extension [KeypointFrame] {
    /// Nearest frame to a playback time, or nil when the gap is larger than
    /// `tolerance` (detection dropouts should show no skeleton, not a stale one).
    func nearest(to seconds: Double, tolerance: Double = 0.25) -> KeypointFrame? {
        guard !isEmpty else { return nil }
        // Frames are time-ordered — binary search for the insertion point.
        var lo = 0, hi = count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if self[mid].t < seconds { lo = mid + 1 } else { hi = mid }
        }
        var best = self[lo]
        if lo > 0, abs(self[lo - 1].t - seconds) < abs(best.t - seconds) {
            best = self[lo - 1]
        }
        return abs(best.t - seconds) <= tolerance ? best : nil
    }
}
