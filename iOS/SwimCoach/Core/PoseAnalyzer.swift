import Vision
import AVFoundation
import CoreML
import Foundation

// Extracts VNHumanBodyPoseObservation from every sampleRate-th frame of a video.
// All AVAssetReader work is dispatched to a background GCD queue so the main thread stays free.
struct PoseAnalyzer {

    static let sampleRate = 3   // process every 3rd frame

    /// A pose observation paired with its source-video presentation time,
    /// so playback overlays can sync the skeleton to the footage.
    struct TimedObservation: @unchecked Sendable {
        let observation: VNHumanBodyPoseObservation
        let seconds: Double
    }

    static func analyze(
        videoURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> (observations: [TimedObservation], fps: Double, sampledFrames: Int) {
        // Cooperative cancellation: the synchronous frame loop polls this flag
        // each frame, so cancelling the wrapping Task (e.g. the user backs out
        // of AnalyzingView) stops the work within one frame instead of running
        // the whole video to completion.
        let cancelled = CancellationFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let result = try analyzeSynchronously(
                            videoURL: videoURL, cancelled: cancelled, onProgress: onProgress)
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancelled.set()
        }
    }

    /// Thread-safe cancellation flag shared between the async wrapper and the
    /// synchronous GCD frame loop.
    final class CancellationFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    // Synchronous inner implementation — must be called off the main thread.
    private static func analyzeSynchronously(
        videoURL: URL,
        cancelled: CancellationFlag,
        onProgress: @escaping @Sendable (Double) -> Void
    ) throws -> (observations: [TimedObservation], fps: Double, sampledFrames: Int) {

        let asset  = AVURLAsset(url: videoURL)
        let tracks = asset.tracks(withMediaType: .video)
        guard let videoTrack = tracks.first else { throw AnalysisError.noVideoTrack }

        let nominalFPS  = videoTrack.nominalFrameRate
        let duration    = CMTimeGetSeconds(asset.duration)
        let totalFrames = max(1, Int(duration * Double(nominalFPS)))

        // Camera files store sensor-native frames + a rotation transform;
        // Vision must be told the orientation or it analyzes sideways
        // content (and returns sideways coordinates).
        let frameOrientation = VideoTransform.orientation(for: videoTrack.preferredTransform)

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
        var observations = [TimedObservation]()
        var frameIndex = 0
        var sampledFrameCount = 0
        var visionErrorCount = 0

        while let sample = output.copyNextSampleBuffer() {
            if cancelled.isSet {
                reader.cancelReading()
                throw CancellationError()
            }
            frameIndex += 1
            // Report progress only on sampled frames — reporting every raw
            // frame spawned thousands of main-actor tasks on long clips.
            guard frameIndex % sampleRate == 0 else { continue }
            onProgress(min(Double(frameIndex) / Double(totalFrames), 1.0))
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            sampledFrameCount += 1

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                orientation: frameOrientation,
                                                options: [:])
            do {
                try handler.perform([request])
                if let results = request.results, !results.isEmpty {
                    // Use shoulder confidence as primary filter — shoulders are reliably detected
                    // even for horizontal swimmers where hip landmarks often fall below threshold.
                    let candidates = results.filter { maxShoulderConfidence($0) > minShoulderConfidence }
                    // Orientation and size are judged per candidate BEFORE ranking: upright
                    // poolside spectators and far-off bystanders are discarded first, so
                    // neither can outrank — and thereby discard — a swimmer whose hips are
                    // occluded.
                    if let index = bestCandidateIndex(candidates.map(poseCandidate)) {
                        let best = candidates[index]
                        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                        observations.append(TimedObservation(
                            observation: best,
                            seconds: pts.isValid ? CMTimeGetSeconds(pts) : Double(frameIndex) / Double(max(nominalFPS, 1))
                        ))
                    }
                }
            } catch {
                visionErrorCount += 1
                if visionErrorCount == 1 {
                    AppLog.analysis.warning("Vision error on frame \(frameIndex): \(String(describing: error))")
                }
            }
        }

        if visionErrorCount > 0 {
            AppLog.analysis.warning("Total Vision errors: \(visionErrorCount)/\(sampledFrameCount) sampled frames")
        }
        AppLog.analysis.info("Sampled \(sampledFrameCount) frames, \(observations.count) swimmer observations")

        return (observations, Double(nominalFPS), sampledFrameCount)
    }

    // MARK: - Candidate selection (pure, unit-tested)

    /// The only three values that decide which detected person a frame keeps.
    /// Lifted out of `VNHumanBodyPoseObservation` — which cannot be constructed
    /// with chosen joint confidences — so the selection rule stays testable.
    struct PoseCandidate {
        /// Torso angle from horizontal, or nil when hip landmarks were undetectable.
        let alignAngle: Float?
        /// Shoulder-midpoint→hip-midpoint distance in normalized frame units,
        /// or nil when the same landmarks were undetectable.
        let torsoLength: Float?
        /// Best of the two shoulder confidences; used only to break ranking ties.
        let shoulderConfidence: Float
    }

    private static let minShoulderConfidence: Float = 0.3

    // Plausible on-screen swimmer size, measured as the normalized distance
    // between the shoulder midpoint and the hip midpoint. Ported from
    // MIN_MEDIAN_TORSO / MAX_MEDIAN_TORSO in ml/analysis/gating.py, which
    // calibrated them against the validation clip set: legitimate 3–6 m footage
    // measures 0.095–0.19, archival far-field race footage 0.084, and crowd
    // shots where the detector stitches two people together 1.06.
    //
    // The numbers compare directly across platforms: both normalize x by frame
    // width and y by frame height on an already-orientation-corrected frame,
    // and the Vision(y-up)→MediaPipe(y-down) flip cancels inside a distance.
    // ml/tests/test_torso_gate_parity.py fails the build if they drift apart.
    static let minTorsoLength: Float = 0.09
    static let maxTorsoLength: Float = 0.60

    /// Index of the candidate most likely to be the swimmer, or nil when every
    /// candidate is clearly upright or implausibly sized (the frame is then dropped).
    ///
    /// Filter, then rank: only horizontal-or-unknown candidates of plausible size
    /// are considered, the flattest of those wins, and equal likelihoods (notably
    /// the unknown-angle sentinel tying with itself) are broken toward the highest
    /// shoulder confidence so the result never depends on Vision's ordering.
    static func bestCandidateIndex(_ candidates: [PoseCandidate]) -> Int? {
        var best: Int?
        for (index, candidate) in candidates.enumerated() where isSwimmerShaped(candidate) {
            guard let incumbent = best else { best = index; continue }
            if ranksAhead(candidate, of: candidates[incumbent]) { best = index }
        }
        return best
    }

    private static func isSwimmerShaped(_ candidate: PoseCandidate) -> Bool {
        isHorizontalOrUnknown(candidate.alignAngle) && isPlausiblySized(candidate.torsoLength)
    }

    private static func ranksAhead(_ lhs: PoseCandidate, of rhs: PoseCandidate) -> Bool {
        let lhsLikelihood = swimmerLikelihood(lhs.alignAngle)
        let rhsLikelihood = swimmerLikelihood(rhs.alignAngle)
        guard lhsLikelihood == rhsLikelihood else { return lhsLikelihood < rhsLikelihood }
        return lhs.shoulderConfidence > rhs.shoulderConfidence
    }

    // Returns the minimum angular distance from horizontal (0=flat, 90=vertical).
    // An unknown angle sorts as vertical so any measurably horizontal body wins.
    private static func swimmerLikelihood(_ alignAngle: Float?) -> Float {
        guard let a = alignAngle else { return 90 }
        return min(a, abs(180 - a))
    }

    // Accepts clearly horizontal bodies AND bodies whose orientation can't be determined
    // (no reliable hip landmarks). The second case covers practice footage where the swimmer
    // is the only person visible, so there are no spectators to reject.
    private static func isHorizontalOrUnknown(_ alignAngle: Float?) -> Bool {
        guard let a = alignAngle else { return true }  // no hip data → accept
        return a < 55 || a > 125
    }

    // Rejects bodies too small to be the filmed swimmer (distant bystanders,
    // far-field race footage) and bodies too large to be a body at all (a torso
    // spanning the frame is the detector stitching two people together).
    //
    // DELIBERATE DEVIATION from `validate_footage` in ml/analysis/gating.py,
    // which applies these bounds to the MEDIAN torso over a whole clip:
    //
    //  * Per candidate, not per clip. Python only ever sees one MediaPipe body
    //    per frame, so a clip-level median is its only lever; Vision hands us
    //    every person in the frame, so the size test belongs where the other
    //    per-person test (orientation) already lives. It is also the safer half
    //    of the trade — a too-small person is dropped from that frame instead of
    //    taking the whole clip down, and a clip whose swimmer is uniformly too
    //    small loses every frame and lands on the existing "no swimmer" /
    //    "too few frames" rejection anyway. Dropped frames are zero-filled onto
    //    FeatureExtractor's uniform time grid, so they cost coverage, not timebase.
    //  * Unmeasurable → accepted. Python measures the torso even when the hips
    //    are low-visibility because MediaPipe always emits an estimated position
    //    for an occluded landmark. Vision does not: an unconfident joint carries
    //    no usable location, so guessing from one would invent a size. iOS
    //    therefore measures only when the angle check's landmarks are present
    //    and treats "unknown size" the way it already treats unknown
    //    orientation — accept, because rejecting a real swimmer whose hips are
    //    under the waterline is far worse than keeping a distant bystander.
    private static func isPlausiblySized(_ torsoLength: Float?) -> Bool {
        guard let length = torsoLength else { return true }  // unmeasurable → accept
        return length >= minTorsoLength && length <= maxTorsoLength
    }

    // MARK: - Vision landmark reads

    private static func poseCandidate(_ obs: VNHumanBodyPoseObservation) -> PoseCandidate {
        // Angle and size come from the same measurement, so a candidate is
        // either fully measured or fully unknown — never half-judged.
        let torso = torsoSegment(obs)
        return PoseCandidate(
            alignAngle: torso.map { abs(atan2($0.dy, $0.dx) * 180 / Float(Double.pi)) },
            torsoLength: torso.map { hypot($0.dx, $0.dy) },
            shoulderConfidence: maxShoulderConfidence(obs))
    }

    private static func maxShoulderConfidence(_ obs: VNHumanBodyPoseObservation) -> Float {
        let left  = (try? obs.recognizedPoint(.leftShoulder))?.confidence ?? 0
        let right = (try? obs.recognizedPoint(.rightShoulder))?.confidence ?? 0
        return max(left, right)
    }

    // Shoulder midpoint → hip midpoint, in Vision's normalized frame coordinates
    // (x by width, y by height, on the orientation-corrected frame). Its angle
    // from horizontal is 0° for a flat swimmer and 90° for a standing person;
    // its magnitude is the swimmer's on-screen size. Vision reports y UP where
    // MediaPipe reports y DOWN, but that flip only negates dy — which `abs`
    // absorbs in the angle and a distance absorbs entirely — so both readings
    // match ml/analysis/gating.py without applying FeatureExtractor's `1 - y`.
    //
    // Returns nil when shoulder or hip landmarks are below confidence threshold:
    // the caller reads that as "orientation and size unknown".
    private static func torsoSegment(_ obs: VNHumanBodyPoseObservation) -> (dx: Float, dy: Float)? {
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
        return (dx: Float(midHX - midSX), dy: Float(midHY - midSY))
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
