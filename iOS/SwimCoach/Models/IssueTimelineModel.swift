import Foundation

/// Pure geometry behind the Results issue-timeline strip.
///
/// Maps per-window model probabilities (`IssueWindow`) plus the detected
/// issues onto normalized, non-overlapping severity segments across the
/// clip duration, and maps a tapped x-fraction back to a seek time.
///
/// Overlap handling (deliberate choice): the strip is a single compact
/// lane, so overlapping detections are MERGED, never stacked —
/// 1. Windows where an issue's probability crosses that issue's own
///    threshold are merged per issue into contiguous runs; a run remembers
///    its start time, which becomes the tap-to-seek target.
/// 2. Runs of different issues are flattened into non-overlapping segments
///    where the highest severity present at each instant wins
///    (major > moderate > minor; ties go to the earlier run). A tap seeks
///    to the start of the winning issue's run — where that fault began.
///
/// If a detected issue never crosses its threshold in any single window
/// (it was flagged from the clip-wide average), its peak window is used as
/// the run so every detected issue still appears on the strip.
///
/// Timebase (easy to get wrong): window times are ABSOLUTE source-video
/// seconds anchored at the first DETECTED frame, while `durationSeconds` is
/// the LENGTH of that detected span, not an end time. The strip is therefore
/// laid out over `[origin, origin + duration]` — where `origin` is the
/// earliest window start — so clips where the swimmer is picked up late are
/// neither shifted nor clamped off the bar. `seekTime` stays absolute
/// because it drives the real player timeline.
struct IssueTimelineModel: Equatable, Sendable {

    struct Segment: Equatable, Sendable {
        /// Normalized span along the clip, both in 0...1.
        let startFraction: Double
        let endFraction: Double
        let severity: TechniqueIssue.Severity
        /// Where tapping this segment seeks: the source run's start (s).
        let seekTime: Double

        var widthFraction: Double { endFraction - startFraction }
    }

    let durationSeconds: Double
    /// Sorted by `startFraction`; pairwise non-overlapping.
    let segments: [Segment]

    /// Severities present on the strip, worst first — drives the legend.
    var legendSeverities: [TechniqueIssue.Severity] {
        Set(segments.map(\.severity)).sorted(by: >)
    }

    // MARK: - Construction

    /// Returns nil whenever the strip should be hidden: nil or empty
    /// windows (legacy sessions), no detected issues, unknown or
    /// non-positive duration, or nothing surviving clamping to the clip.
    /// Duration is validated before any division — never divides by zero.
    static func make(windows: [IssueWindow]?,
                     issues: [TechniqueIssue],
                     durationSeconds: Double?) -> IssueTimelineModel? {
        guard let windows, !windows.isEmpty, !issues.isEmpty,
              let duration = durationSeconds,
              duration.isFinite, duration > 0 else { return nil }

        // Anchor to the detected span's own start rather than assuming 0.
        // `windowRanges` always emits a range with lowerBound 0, so the
        // earliest window start is exactly the extractor's `t0`.
        let origin = windows.map(\.start).filter(\.isFinite).min() ?? 0

        let runs = issueRuns(windows: windows, issues: issues,
                             origin: origin, duration: duration)
        let segments = flatten(runs: runs, origin: origin, duration: duration)
        guard !segments.isEmpty else { return nil }
        return IssueTimelineModel(durationSeconds: duration, segments: segments)
    }

    // MARK: - Hit-testing

    /// Seek time for a tap at a normalized x-fraction of the bar. Out-of-
    /// range fractions clamp to 0...1; taps on empty track return nil.
    func seekTime(atFraction fraction: Double) -> Double? {
        guard fraction.isFinite else { return nil }
        let f = min(max(fraction, 0), 1)
        return segments.first {
            f >= $0.startFraction - Self.epsilon && f <= $0.endFraction + Self.epsilon
        }?.seekTime
    }

    // MARK: - Internals

    private static let epsilon = 1e-9

    /// A contiguous stretch of the clip where one issue was active.
    private struct Run {
        let start: Double
        let end: Double
        let severity: TechniqueIssue.Severity
    }

    /// Per-issue threshold-crossing windows (peak-window fallback when none
    /// cross), clamped to the detected span and merged into contiguous runs.
    private static func issueRuns(windows: [IssueWindow],
                                  issues: [TechniqueIssue],
                                  origin: Double,
                                  duration: Double) -> [Run] {
        let clipEnd = origin + duration
        return issues.flatMap { issue -> [Run] in
            guard let index = FeedbackEngine.labelIndex(of: issue.name) else { return [] }
            var active = windows.filter {
                $0.probs.indices.contains(index) && Double($0.probs[index]) >= issue.threshold
            }
            if active.isEmpty, let peak = windows.peakWindow(labelIndex: index) {
                active = [peak]
            }
            let clamped: [(start: Double, end: Double)] = active.compactMap { w in
                let s = min(max(w.start, origin), clipEnd)
                let e = min(max(w.end, origin), clipEnd)
                return e - s > epsilon ? (s, e) : nil
            }
            return merge(intervals: clamped, severity: issue.severity)
        }
    }

    /// Coalesces overlapping or touching intervals of one issue.
    private static func merge(intervals: [(start: Double, end: Double)],
                              severity: TechniqueIssue.Severity) -> [Run] {
        intervals
            .sorted { $0.start < $1.start }
            .reduce(into: [Run]()) { runs, interval in
                if let last = runs.last, interval.start <= last.end + epsilon {
                    runs[runs.count - 1] = Run(start: last.start,
                                               end: max(last.end, interval.end),
                                               severity: severity)
                } else {
                    runs.append(Run(start: interval.start,
                                    end: interval.end,
                                    severity: severity))
                }
            }
    }

    /// Boundary-sweeps all runs into sorted, non-overlapping segments where
    /// the highest severity at each instant wins.
    private static func flatten(runs: [Run],
                                origin: Double,
                                duration: Double) -> [Segment] {
        guard !runs.isEmpty else { return [] }
        let bounds = Set(runs.flatMap { [$0.start, $0.end] }).sorted()
        var segments: [Segment] = []
        for (sliceStart, sliceEnd) in zip(bounds, bounds.dropFirst())
        where sliceEnd - sliceStart > epsilon {
            let mid = (sliceStart + sliceEnd) / 2
            let covering = runs.filter { mid > $0.start - epsilon && mid < $0.end + epsilon }
            guard let winner = covering.max(by: { lhs, rhs in
                if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
                return lhs.start > rhs.start   // tie → earlier run wins
            }) else { continue }

            let startF = (sliceStart - origin) / duration
            let endF = (sliceEnd - origin) / duration
            if let last = segments.last,
               last.severity == winner.severity,
               last.seekTime == winner.start,
               abs(last.endFraction - startF) < epsilon {
                segments[segments.count - 1] = Segment(startFraction: last.startFraction,
                                                       endFraction: endF,
                                                       severity: last.severity,
                                                       seekTime: last.seekTime)
            } else {
                segments.append(Segment(startFraction: startF,
                                        endFraction: endF,
                                        severity: winner.severity,
                                        seekTime: winner.start))
            }
        }
        return segments
    }
}
