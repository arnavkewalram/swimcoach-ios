import Foundation

/// Per-session stroke-mechanics series for the History trend chart.
/// Pure — built from cheap stored `SwimSession` scalars (never from the
/// encoded result blob) and unit-tested.
struct MetricTrend: Equatable {
    /// Cheap per-session inputs, one per swimmer-scoped session.
    struct Entry: Equatable {
        let date: Date
        let strokeCount: Int
        let durationSeconds: Double
        let kickRatePerMin: Double

        init(date: Date, strokeCount: Int,
             durationSeconds: Double, kickRatePerMin: Double) {
            self.date = date
            self.strokeCount = strokeCount
            self.durationSeconds = durationSeconds
            self.kickRatePerMin = kickRatePerMin
        }
    }

    struct Point: Equatable {
        /// 1-based position in the chronological session sequence — the
        /// shared integer X axis used by the score trend chart.
        let index: Int
        let value: Double
        /// Contiguity run. Consecutive plottable sessions share a run so
        /// the chart breaks the line where a session is missing the metric
        /// instead of drawing across the gap.
        let run: Int
    }

    struct Series: Equatable {
        let points: [Point]
        /// Most recent plottable value (series is chronological).
        var latest: Double? { points.last?.value }
    }

    /// Total sessions in the sequence (plottable or not) — the X domain.
    let sessionCount: Int
    /// Strokes per minute, derived from stored count + stored duration.
    let strokeRate: Series
    /// Kicks per minute, stored directly on the session.
    let kickRate: Series

    /// A trend is worth drawing once some series has two plottable sessions.
    var isPlottable: Bool {
        strokeRate.points.count >= 2 || kickRate.points.count >= 2
    }

    /// "Latest: 34 strokes/min · 102 kicks/min" — omits series with no
    /// data; nil when neither series has any.
    var caption: String? {
        let parts = [
            strokeRate.latest.map { "\(Int($0.rounded())) strokes/min" },
            kickRate.latest.map { "\(Int($0.rounded())) kicks/min" },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : "Latest: " + parts.joined(separator: " · ")
    }

    /// Builds both series from session entries in any order; sessions are
    /// sorted chronologically (oldest first) before indexing. Zero or
    /// missing values are never plotted — they become gaps.
    static func build(entries: [Entry]) -> MetricTrend {
        let ordered = entries.sorted { $0.date < $1.date }
        return MetricTrend(
            sessionCount: ordered.count,
            strokeRate: series(over: ordered) { entry in
                guard entry.strokeCount > 0, entry.durationSeconds > 0 else { return nil }
                return Double(entry.strokeCount) * 60 / entry.durationSeconds
            },
            kickRate: series(over: ordered) { entry in
                entry.kickRatePerMin > 0 ? entry.kickRatePerMin : nil
            })
    }

    /// Maps chronological entries to gapped points, tagging contiguity runs.
    private static func series(over ordered: [Entry],
                               value: (Entry) -> Double?) -> Series {
        var points: [Point] = []
        var run = 0
        for (offset, entry) in ordered.enumerated() {
            guard let value = value(entry) else { continue }
            let index = offset + 1
            if let last = points.last, last.index != index - 1 {
                run += 1
            }
            points.append(Point(index: index, value: value, run: run))
        }
        return Series(points: points)
    }
}
