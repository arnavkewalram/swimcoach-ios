import Vision
import CoreML

// Converts Vision pose observations into (1, 39, 90) MLMultiArray windows for SwimTCN.
// Joint order matches KEYPOINT_NAMES in swim-analyzer/pose/extractor.py exactly.
//
// The model is trained on 90-frame windows at 30 fps (3 s). Observations arrive at
// effectiveFPS (~10 fps after PoseAnalyzer's frame sampling), so we slide windows of
// 3 s worth of observations and resample each to 90 frames. Squeezing the whole clip
// into a single window would time-compress it and distort frequency-sensitive labels
// (kick rate) in proportion to clip length.
struct FeatureExtractor {

    static let joints: [VNHumanBodyPoseObservation.JointName] = [
        .nose,
        .leftShoulder,  .rightShoulder,
        .leftElbow,     .rightElbow,
        .leftWrist,     .rightWrist,
        .leftHip,       .rightHip,
        .leftKnee,      .rightKnee,
        .leftAnkle,     .rightAnkle,
    ]

    static let nJoints   = 13
    static let nCoords   = 3    // x, y, confidence
    static let targetLen = 90   // model window length (frames @ 30 fps)
    static let windowSeconds = 3.0
    static let minObservations = 5

    // MARK: - Public API

    static func extractWindows(
        from observations: [VNHumanBodyPoseObservation],
        effectiveFPS: Double
    ) -> [MLMultiArray]? {
        guard observations.count >= minObservations else { return nil }

        let W = nJoints * nCoords
        let raw = rawBuffer(from: observations)
        let winLen = windowLength(for: effectiveFPS)
        let tensors = windowRanges(frameCount: observations.count, windowLen: winLen)
            .compactMap { r -> MLMultiArray? in
                tensor(from: Array(raw[(r.lowerBound * W)..<(r.upperBound * W)]),
                       frameCount: r.count)
            }
        return tensors.isEmpty ? nil : tensors
    }

    // 3 s worth of observations at the pipeline's effective frame rate.
    static func windowLength(for effectiveFPS: Double) -> Int {
        max(minObservations, Int((windowSeconds * max(1.0, effectiveFPS)).rounded()))
    }

    // Sliding ranges with 50% overlap; the final window is flush with the clip
    // end. Clips shorter than one window yield a single whole-clip range
    // (stretched by resampling — bounded distortion for sub-3s clips).
    static func windowRanges(frameCount: Int, windowLen: Int) -> [Range<Int>] {
        guard frameCount > windowLen else { return [0..<frameCount] }
        let step = max(1, windowLen / 2)
        var starts = Array(stride(from: 0, through: frameCount - windowLen, by: step))
        if starts.last != frameCount - windowLen {
            starts.append(frameCount - windowLen)
        }
        return starts.map { $0..<($0 + windowLen) }
    }

    // MARK: - Internals

    // Flat (T × 39) buffer: [t*W + j*3 + c]
    private static func rawBuffer(from observations: [VNHumanBodyPoseObservation]) -> [Float] {
        let W = nJoints * nCoords
        var raw = [Float](repeating: 0, count: observations.count * W)
        for (t, obs) in observations.enumerated() {
            for (j, joint) in joints.enumerated() {
                let base = t * W + j * nCoords
                if let pt = try? obs.recognizedPoint(joint), pt.confidence > 0.1 {
                    raw[base]     = Float(pt.location.x)
                    // Vision uses a bottom-left origin (y up); the model was trained on
                    // MediaPipe keypoints with a top-left origin (y down). Flip to match.
                    raw[base + 1] = Float(1 - pt.location.y)
                    raw[base + 2] = Float(pt.confidence)
                }
            }
        }
        return raw
    }

    // Pack one window (frameCount × 39 flat) into a (1, 39, targetLen) tensor.
    // Layout: tensor[channel * targetLen + t] where channel = j*3 + c.
    private static func tensor(from raw: [Float], frameCount: Int) -> MLMultiArray? {
        let W = nJoints * nCoords
        let resampled = frameCount == targetLen
            ? raw
            : resample(raw, fromLen: frameCount, width: W)

        guard let tensor = try? MLMultiArray(
            shape: [1, W, targetLen] as [NSNumber], dataType: .float32
        ) else { return nil }

        let ptr = tensor.dataPointer.assumingMemoryBound(to: Float32.self)
        for t in 0..<targetLen {
            for channel in 0..<W {
                ptr[channel * targetLen + t] = resampled[t * W + channel]
            }
        }
        return tensor
    }

    private static func resample(_ src: [Float], fromLen T: Int, width W: Int) -> [Float] {
        var out = [Float](repeating: 0, count: targetLen * W)
        for i in 0..<targetLen {
            let pos  = Double(i) * Double(T - 1) / Double(targetLen - 1)
            let lo   = Int(pos)
            let hi   = min(lo + 1, T - 1)
            let frac = Float(pos - Double(lo))
            for w in 0..<W {
                out[i * W + w] = src[lo * W + w] * (1 - frac) + src[hi * W + w] * frac
            }
        }
        return out
    }
}
