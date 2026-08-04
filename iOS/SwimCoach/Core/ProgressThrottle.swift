import Foundation

/// Whole-percent gate for a progress callback that fires once per processed
/// frame.
///
/// Both long-running pipelines have the same shape: a synchronous frame loop on
/// a background queue, a `@Sendable` progress closure, and a SwiftUI view that
/// hops to the main actor on every report. Reporting each raw frame spawns a
/// main-actor task per frame — ~1800 on a 60 s clip — and each one re-runs a
/// view body. Gating on the whole percent caps any run at 101 reports (0...100)
/// while still emitting every distinct value the UI can render, since both
/// screens display `Int(fraction * 100)`.
///
/// Lives here rather than inside either caller: it was written for
/// `OverlayVideoExporter` in v1.45.6 and `AnalyzingView`'s pose phase needs the
/// identical gate. One implementation, one set of tests.
///
/// Callers create one instance per run and let it fall out of scope at the end,
/// so there is no reset to forget — a retry gets a fresh gate.
///
/// The pump blocks that use this are `@Sendable`, so the running percent cannot
/// be a captured `var`. In practice it advances on a single queue, but the lock
/// keeps that assumption from being load-bearing.
final class ProgressThrottle: @unchecked Sendable {

    /// Whole-percent bucket for a progress fraction, clamped to 0...100.
    /// Pure — unit-tested.
    static func percentStep(_ fraction: Double) -> Int {
        Int(min(max(fraction, 0), 1) * 100)
    }

    /// The gate itself: report only when the whole percent advances.
    /// Pure — unit-tested.
    static func shouldReport(fraction: Double, lastReported: Int) -> Bool {
        percentStep(fraction) > lastReported
    }

    private let lock = NSLock()
    private var lastReported = -1

    /// True — and advances the gate — when `fraction` crosses into a whole
    /// percent not yet reported. Starts below zero so 0.0 always reports.
    func admit(_ fraction: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard ProgressThrottle.shouldReport(fraction: fraction,
                                            lastReported: lastReported) else { return false }
        lastReported = ProgressThrottle.percentStep(fraction)
        return true
    }
}
