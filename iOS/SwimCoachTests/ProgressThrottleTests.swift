import XCTest
@testable import SwimCoach

/// The whole-percent gate shared by `OverlayVideoExporter` (encode pump) and
/// `AnalyzingView`'s pose phase (sampled-frame pump). Both drive it from a
/// background queue and hop to the main actor on every admitted report, so the
/// count it admits is the count of view-body invalidations.
final class ProgressThrottleTests: XCTestCase {

    // MARK: - Pure gate

    func testShouldReportGatesOnWholePercentChange() {
        // Fresh gate starts below zero so the opening 0.0 always reports.
        XCTAssertTrue(ProgressThrottle.shouldReport(fraction: 0, lastReported: -1))
        XCTAssertFalse(ProgressThrottle.shouldReport(fraction: 0.0049, lastReported: 0))
        XCTAssertTrue(ProgressThrottle.shouldReport(fraction: 0.0149, lastReported: 0))
        XCTAssertFalse(ProgressThrottle.shouldReport(fraction: 0.994, lastReported: 99))
        XCTAssertTrue(ProgressThrottle.shouldReport(fraction: 1.0, lastReported: 99))
        XCTAssertFalse(ProgressThrottle.shouldReport(fraction: 1.0, lastReported: 100))
    }

    func testPercentStepClampsOutOfRangeFractions() {
        XCTAssertEqual(ProgressThrottle.percentStep(-0.5), 0)
        XCTAssertEqual(ProgressThrottle.percentStep(0), 0)
        XCTAssertEqual(ProgressThrottle.percentStep(0.5), 50)
        XCTAssertEqual(ProgressThrottle.percentStep(1.0), 100)
        XCTAssertEqual(ProgressThrottle.percentStep(1.7), 100)
    }

    func testThrottleReportsBothEndpoints() {
        let throttle = ProgressThrottle()
        XCTAssertTrue(throttle.admit(0))
        XCTAssertTrue(throttle.admit(1.0))
        XCTAssertFalse(throttle.admit(1.0), "100% reports at most once")
    }

    func testThrottleAdmitsCompletionAfterShortFinalFrame() {
        // A clip whose last decoded frame lands at 99.4% must still be able to
        // report the exporter's terminal 1.0.
        let throttle = ProgressThrottle()
        XCTAssertTrue(throttle.admit(0.994))
        XCTAssertTrue(throttle.admit(1.0))
    }

    func testThrottleStepsMonotonicallyAndCapsLongRun() {
        // 60 s at 30 fps — 1800 unthrottled pump iterations.
        let frameCount = 1800
        let throttle = ProgressThrottle()
        var reported = [Double]()
        for i in 0..<frameCount {
            let fraction = Double(i) / Double(frameCount - 1)
            if throttle.admit(fraction) { reported.append(fraction) }
        }

        XCTAssertLessThanOrEqual(reported.count, 101)
        XCTAssertEqual(reported.first ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(reported.last ?? -1, 1.0, accuracy: 1e-9)

        let percents = reported.map { ProgressThrottle.percentStep($0) }
        XCTAssertEqual(percents, percents.sorted(), "reports must step monotonically")
        XCTAssertEqual(Set(percents).count, percents.count, "each whole percent reports once")
    }

    // MARK: - Analysis pose phase (composite bar)

    /// `AnalyzingView` gates on the composite bar value, not on the raw phase
    /// fraction, so the gate's percents are the bar's percents.
    func testPosePhaseMapsFractionOntoItsSliceOfTheBar() {
        XCTAssertEqual(AnalyzingView.poseProgress(for: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(AnalyzingView.poseProgress(for: 0.5), 0.30, accuracy: 1e-9)
        XCTAssertEqual(AnalyzingView.poseProgress(for: 1.0),
                       AnalyzingView.poseProgressShare, accuracy: 1e-9)
    }

    /// The pose pump on a 60 s clip: PoseAnalyzer reports every 3rd frame, so
    /// 600 raw reports. Throttled they must start at 0, step monotonically, and
    /// collapse to the 61 whole percents this phase can actually render.
    func testPosePhaseStartsAtZeroAndCapsAtItsRenderableSteps() {
        let sampledFrames = 600
        let throttle = ProgressThrottle()
        var reported = [Double]()
        for i in 0..<sampledFrames {
            let fraction = Double(i) / Double(sampledFrames - 1)
            let bar = AnalyzingView.poseProgress(for: fraction)
            if throttle.admit(bar) { reported.append(bar) }
        }

        XCTAssertEqual(reported.first ?? -1, 0, accuracy: 1e-9,
                       "the bar must still open at 0")
        XCTAssertEqual(reported, reported.sorted(), "bar must advance monotonically")
        XCTAssertLessThanOrEqual(reported.count, 61,
                                 "0…60% is at most 61 renderable steps — one main-actor write each")
        XCTAssertLessThan(reported.count, sampledFrames / 5,
                          "throttle must be a real reduction on the pump's report rate")
        XCTAssertEqual(reported.last ?? -1, AnalyzingView.poseProgressShare, accuracy: 0.01,
                       "phase must reach its own ceiling")

        // Contiguous from 0: the bar shows every whole percent it passes, once.
        let percents = reported.map { ProgressThrottle.percentStep($0) }
        XCTAssertEqual(percents, Array(0...(percents.last ?? 0)))
    }

    /// PoseAnalyzer's last sampled frame lands short of the end (it only reports
    /// on every 3rd frame, so `frameIndex / totalFrames` stops a frame or two
    /// below 1.0). The throttle must not be the thing that decides where the
    /// phase ends: whatever it last admitted has to stay strictly below the next
    /// stage's unconditional 0.65, so the handoff is forward, never a jump back.
    func testPosePhaseHandoffToNextStageNeverGoesBackwards() {
        let nextStageValue = 0.65   // `await update(progress: 0.65)` in runAnalysis
        // Sweep plausible short endings for the last sampled frame.
        for shortfall in [0.0, 0.001, 0.003, 0.01, 0.05] {
            let throttle = ProgressThrottle()
            var last = -1.0
            for i in 0...100 {
                let fraction = min(Double(i) / 100.0, 1.0 - shortfall)
                let bar = AnalyzingView.poseProgress(for: fraction)
                if throttle.admit(bar) { last = bar }
            }
            XCTAssertGreaterThanOrEqual(last, 0, "phase must report at least once")
            XCTAssertLessThan(last, nextStageValue,
                              "stage 2 must resume above where pose stopped (shortfall \(shortfall))")
        }
    }

    /// "Try again" builds a new throttle rather than resetting one, so a retry
    /// re-reports 0% instead of staying dark until it passes the old high-water
    /// mark. This pins that the gate genuinely is per-run state.
    func testFreshThrottlePerRunReportsZeroAgain() {
        let firstRun = ProgressThrottle()
        XCTAssertTrue(firstRun.admit(0))
        XCTAssertTrue(firstRun.admit(0.42))
        XCTAssertFalse(firstRun.admit(0), "a run never walks its own gate backwards")

        let retry = ProgressThrottle()
        XCTAssertTrue(retry.admit(0), "a retry must be able to show 0% again")
    }
}
