import Vision
import Foundation

// Computes observable swim metrics (stroke count, kick rate, asymmetry) from Vision
// pose observations, plus score/grade aggregation over ML-detected issues.
// Issue detection itself is the SwimTCN CoreML model (see SwimTCNRunner/FeedbackEngine).
struct BiomechanicsEngine {

    // MARK: - Public types

    struct Metrics {
        var strokeCount: Int    = 0
        var kickRatePerMin: Double = 0
        var strokeAsymmetry: Double = 0
    }

    // MARK: - Metrics (always called)

    func metrics(
        from timed: [PoseAnalyzer.TimedObservation],
        fps: Double,
        sampleRate: Int,
        sampledFrames: Int = 0
    ) -> Metrics {
        let effectiveFPS = fps / Double(max(1, sampleRate))
        // Real elapsed time from timestamps — observation-count-based duration
        // understates elapsed time whenever detection drops frames, which
        // inflated kick rate on clean footage and zeroed it on sparse footage.
        let realDuration: Double
        if let first = timed.first?.seconds, let last = timed.last?.seconds, last > first {
            realDuration = (last - first) + 1.0 / max(1.0, effectiveFPS)
        } else {
            realDuration = Double(max(sampledFrames, timed.count)) / max(1.0, effectiveFPS)
        }
        let motion = computeMotion(timed.map(\.observation),
                                   effectiveFPS: effectiveFPS,
                                   overrideDuration: realDuration)
        return Metrics(
            strokeCount: motion.totalStrokes,
            kickRatePerMin: motion.kickRate,
            strokeAsymmetry: motion.asymmetry
        )
    }

    // MARK: - Scoring

    static func score(from issues: [TechniqueIssue]) -> Int {
        let deduction = issues.reduce(0) { acc, i in
            acc + (i.severity == .major ? 25 : i.severity == .moderate ? 15 : 5)
        }
        return max(0, 100 - deduction)
    }

    static func grade(from score: Int) -> String {
        switch score {
        case 90...: return "A"
        case 80..<90: return "B"
        case 70..<80: return "C"
        case 60..<70: return "D"
        default: return "F"
        }
    }

    // MARK: - Joint access

    private func pt(_ o: VNHumanBodyPoseObservation,
                    _ j: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
        // Hips use a lower threshold — they're partially occluded in side-view pool footage
        let threshold: Float = (j == .leftHip || j == .rightHip) ? 0.25 : 0.35
        guard let p = try? o.recognizedPoint(j), p.confidence > threshold else { return nil }
        return p.location
    }

    // MARK: - Motion computation

    private struct MotionData {
        var lStrokes: Int = 0
        var rStrokes: Int = 0
        var totalStrokes: Int = 0  // may include shoulder-oscillation fallback
        var kickRate: Double = 0
        var nKicks: Int = 0
        var duration: Double = 0
        var asymmetry: Double = 0
    }

    private func computeMotion(_ obs: [VNHumanBodyPoseObservation],
                                effectiveFPS: Double,
                                overrideDuration: Double? = nil) -> MotionData {
        var lWrist = [Float](), rWrist = [Float]()
        var lAnkle = [Float](), rAnkle = [Float]()
        var shoulderDiff = [Float]()  // leftShoulder.y − rightShoulder.y

        for o in obs {
            lWrist.append(pt(o, .leftWrist).map  { Float($0.y) } ?? lWrist.last  ?? 0.5)
            rWrist.append(pt(o, .rightWrist).map { Float($0.y) } ?? rWrist.last  ?? 0.5)
            lAnkle.append(pt(o, .leftAnkle).map  { Float($0.y) } ?? lAnkle.last  ?? 0.8)
            rAnkle.append(pt(o, .rightAnkle).map { Float($0.y) } ?? rAnkle.last  ?? 0.8)
            if let ls = pt(o, .leftShoulder), let rs = pt(o, .rightShoulder) {
                shoulderDiff.append(Float(ls.y - rs.y))
            }
        }

        // Primary: wrist-based stroke counting (reliable when wrists are detected).
        let lS = peaks(lWrist), rS = peaks(rWrist)
        var totalStrokes = lS.count + rS.count

        // Fallback: shoulder-oscillation stroke counting.
        // In freestyle the shoulders rock alternately — positive peaks = left arm pulling,
        // troughs (negative peaks) = right arm pulling. Count both directions.
        if totalStrokes < 4 && shoulderDiff.count >= 6 {
            let posPeaks = peaks(shoulderDiff)
            let negPeaks = peaks(shoulderDiff.map { -$0 })
            let shoulderStrokes = posPeaks.count + negPeaks.count
            if shoulderStrokes > totalStrokes {
                totalStrokes = shoulderStrokes
            }
        }

        let nKicks = peaks(lAnkle).count + peaks(rAnkle).count
        let duration = overrideDuration
            ?? (obs.isEmpty ? 1.0 : Double(obs.count) / max(1, effectiveFPS))
        let kickRate = Double(nKicks) / duration * 60.0
        let diff = abs(lS.count - rS.count)
        let total = max(1, lS.count + rS.count)
        return MotionData(lStrokes: lS.count, rStrokes: rS.count,
                          totalStrokes: totalStrokes,
                          kickRate: kickRate, nKicks: nKicks, duration: duration,
                          asymmetry: Double(diff) / Double(total))
    }

    private func peaks(_ sig: [Float], minDist: Int = 8) -> [Int] {
        guard sig.count > 4 else { return [] }
        let s = smooth(sig)
        var result = [Int]()
        for i in 1..<s.count - 1 where s[i] > s[i-1] && s[i] > s[i+1] {
            if result.isEmpty || i - result.last! >= minDist { result.append(i) }
        }
        return result
    }

    private func smooth(_ sig: [Float], w: Int = 5) -> [Float] {
        let half = w / 2
        return sig.indices.map { i in
            let lo = max(0, i - half), hi = min(sig.count - 1, i + half)
            let s  = sig[lo...hi]; return s.reduce(0, +) / Float(s.count)
        }
    }
}
