import Vision
import AVFoundation
import CoreML
import Foundation

// Extracts VNHumanBodyPoseObservation from every sampleRate-th frame of a video.
// All AVAssetReader work is dispatched to a background GCD queue so the main thread stays free.
struct PoseAnalyzer {

    static let sampleRate = 3   // process every 3rd frame

    static func analyze(
        videoURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> (observations: [VNHumanBodyPoseObservation], fps: Double, sampledFrames: Int) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try analyzeSynchronously(videoURL: videoURL, onProgress: onProgress)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // Synchronous inner implementation — must be called off the main thread.
    private static func analyzeSynchronously(
        videoURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) throws -> (observations: [VNHumanBodyPoseObservation], fps: Double, sampledFrames: Int) {

        let asset  = AVURLAsset(url: videoURL)
        let tracks = asset.tracks(withMediaType: .video)
        guard let videoTrack = tracks.first else { throw AnalysisError.noVideoTrack }

        let nominalFPS  = videoTrack.nominalFrameRate
        let duration    = CMTimeGetSeconds(asset.duration)
        let totalFrames = max(1, Int(duration * Double(nominalFPS)))

        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            throw AnalysisError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }

        // NOTE: VNDetectHumanBodyPoseRequest cannot run in the iOS Simulator
        // (every frame fails with error 9 "Unable to setup request"; neither
        // usesCPUOnly nor setComputeDevice(.cpu) helps on the iOS 26 runtime).
        // Real pose extraction requires a physical device. The simulator path
        // fails gracefully into the "No horizontal swimmer detected" message.
        let request = VNDetectHumanBodyPoseRequest()
        var observations = [VNHumanBodyPoseObservation]()
        var frameIndex = 0
        var sampledFrameCount = 0
        var visionErrorCount = 0

        while let sample = output.copyNextSampleBuffer() {
            frameIndex += 1
            onProgress(min(Double(frameIndex) / Double(totalFrames), 1.0))

            guard frameIndex % sampleRate == 0 else { continue }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            sampledFrameCount += 1

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([request])
                if let results = request.results, !results.isEmpty {
                    // Use shoulder confidence as primary filter — shoulders are reliably detected
                    // even for horizontal swimmers where hip landmarks often fall below threshold.
                    let candidates = results.filter { obs in
                        (try? obs.recognizedPoint(.leftShoulder))?.confidence ?? 0 > 0.3 ||
                        (try? obs.recognizedPoint(.rightShoulder))?.confidence ?? 0 > 0.3
                    }
                    if let best = candidates.min(by: { a, b in
                        swimmerLikelihood(a) < swimmerLikelihood(b)
                    }) {
                        // When hip data is available we check body orientation to reject upright
                        // poolside spectators. When hips aren't detected we assume the shoulder
                        // detection belongs to the swimmer (the only person in a practice video).
                        if isHorizontalSwimmerOrUnknown(best) {
                            observations.append(best)
                        }
                    }
                }
            } catch {
                visionErrorCount += 1
                if visionErrorCount == 1 {
                    print("[PoseAnalyzer] Vision error on frame \(frameIndex): \(error)")
                }
            }
        }

        if visionErrorCount > 0 {
            print("[PoseAnalyzer] Total Vision errors: \(visionErrorCount)/\(sampledFrameCount) sampled frames")
        }
        print("[PoseAnalyzer] Sampled \(sampledFrameCount) frames, \(observations.count) observations with visible hips")

        return (observations, Double(nominalFPS), sampledFrameCount)
    }

    // Returns the minimum angular distance from horizontal (0=flat, 90=vertical, nil=unknown).
    // nil means hip landmarks weren't detectable — caller should treat as "probably horizontal".
    private static func swimmerLikelihood(_ obs: VNHumanBodyPoseObservation) -> Float {
        guard let a = bodyAlignAngle(obs) else { return 90 }  // unknown → treat as vertical for sorting
        return min(a, abs(180 - a))
    }

    // Accepts clearly horizontal bodies AND bodies whose orientation can't be determined
    // (no reliable hip landmarks). The second case covers practice footage where the swimmer
    // is the only person visible, so there are no spectators to reject.
    private static func isHorizontalSwimmerOrUnknown(_ obs: VNHumanBodyPoseObservation) -> Bool {
        guard let a = bodyAlignAngle(obs) else { return true }  // no hip data → accept
        return a < 55 || a > 125
    }

    // Returns the torso angle from horizontal (0° = flat swimmer, 90° = standing person).
    // Returns nil when shoulder or hip landmarks are below confidence threshold.
    private static func bodyAlignAngle(_ obs: VNHumanBodyPoseObservation) -> Float? {
        guard
            let ls = (try? obs.recognizedPoint(.leftShoulder)),  ls.confidence > 0.2,
            let rs = (try? obs.recognizedPoint(.rightShoulder)), rs.confidence > 0.2,
            let lh = (try? obs.recognizedPoint(.leftHip)),       lh.confidence > 0.15,
            let rh = (try? obs.recognizedPoint(.rightHip)),      rh.confidence > 0.15
        else { return nil }
        let midSX = (ls.location.x + rs.location.x) / 2
        let midSY = (ls.location.y + rs.location.y) / 2
        let midHX = (lh.location.x + rh.location.x) / 2
        let midHY = (lh.location.y + rh.location.y) / 2
        let dx = Float(midHX - midSX), dy = Float(midHY - midSY)
        return abs(atan2(dy, dx) * 180 / Float(Double.pi))
    }
}

enum AnalysisError: LocalizedError {
    case noVideoTrack
    case readerFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:        return "No video track found in recording."
        case .readerFailed(let m): return "Video reading failed: \(m)"
        }
    }
}
