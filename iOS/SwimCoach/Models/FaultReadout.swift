import Foundation

/// One fault the model scores, and how strongly it read on this clip — the
/// data behind the Results "Full read-out" section. Pure; unit-tested.
///
/// The app has always scored ten faults and reported only the two or three
/// that cross `FeedbackEngine.threshold`. Every channel is already on disk
/// (`AnalysisResult.issueWindows`, stored since v1.1.0), so nothing new is
/// computed or persisted here — this type only recovers what was thrown away
/// at display time.
///
/// EXACTNESS (load-bearing). `AnalyzingView` builds the vector it hands to
/// `FeedbackEngine.decode` by summing each window's `probs` in window order
/// into a `[Float]` accumulator and dividing by the window count:
///
///     var probSum = [Float](repeating: 0, count: 10)
///     for w in tensors { … for i in probSum.indices { probSum[i] += p[i] } }
///     let probs = probSum.map { $0 / Float(tensors.count) }
///
/// …and appends that same `p` to `windows`. `mean` below repeats that
/// arithmetic exactly — same order, same `Float` type, same divisor — so for
/// any session that stored its windows these are not estimates of what
/// `decode` saw. They are the identical `Float` values, bit for bit, which is
/// why `band == .flagged` and "appears in `AnalysisResult.issues`" cannot
/// disagree. Do NOT "improve" this to a `Double` accumulator, to `reduce`
/// with a different association, or to a per-channel divisor: each of those
/// silently breaks the equality and this section starts contradicting the
/// Issues section above it.
struct FaultReadout: Hashable, Sendable, Identifiable {

    /// Where a reading landed relative to `FeedbackEngine`'s bar.
    ///
    /// Declared strongest-first: `allCases` is the section's display order,
    /// and because the bands are cut-points on the value `ranked(from:)`
    /// sorts by, one descending sort already groups them.
    enum Band: Int, Hashable, Sendable, CaseIterable {
        /// At or above the bar. This fault IS in `AnalysisResult.issues`.
        case flagged
        /// Under the bar but within reach of it. **Not** a detection.
        case close
        /// Well under the bar. Nothing was seen.
        case clear
    }

    /// Catalog name (`FeedbackEngine.issueNames[channel]`).
    let name: String
    /// Catalog display name.
    let displayName: String
    /// Channel index in catalog / `IssueWindow.probs` order.
    let channel: Int
    /// Clip-wide mean — the exact value `FeedbackEngine.decode` was given.
    let mean: Float
    /// Strongest single window. Never below `mean`, the model's outputs being
    /// non-negative by construction (see the range note on `closeFraction`).
    let peak: Float

    var id: String { name }

    var band: Band { Self.band(for: mean) }

    var meanPercent: Int { Self.percent(mean) }
    var peakPercent: Int { Self.percent(peak) }

    /// Whether the peak is worth printing beside the mean. A fault that sat
    /// flat across the clip has nothing extra to say, and a second number
    /// that repeats the first is noise on a ten-row table.
    var showsPeak: Bool { peakPercent > meanPercent }
}

// MARK: - Bands

extension FaultReadout {

    /// The bar a fault must reach to be reported. Owned by `FeedbackEngine`;
    /// never restate the number here — this section has to move with it.
    static var flagBar: Float { FeedbackEngine.threshold }

    /// How far under the bar still counts as "close", as a fraction of the
    /// bar itself rather than a fixed epsilon, so the band tracks the
    /// threshold if it ever moves.
    ///
    /// Two-thirds puts the floor at 30%, which is the midpoint of everything
    /// the model can say below the bar: `SwimTCN.forward()` clamps its logits
    /// to ±1.9, so probabilities are bounded to (0.13, 0.87) by construction
    /// and the sub-threshold range is [0.13, 0.45). "Close" is therefore its
    /// upper half — a real half, not a sliver, and not most of the scale.
    static let closeFraction: Float = 2.0 / 3.0

    /// Lowest reading that still counts as close.
    static var closeFloor: Float { flagBar * closeFraction }

    static func band(for mean: Float) -> Band {
        // Same comparison `decode` makes, so the flagged band and the Issues
        // section can never disagree about a boundary reading.
        if mean >= flagBar { return .flagged }
        if mean >= closeFloor { return .close }
        return .clear
    }

    /// The one rounding rule for this section — copy and rows share it, so a
    /// row can never print a number its own band caption contradicts.
    static func percent(_ value: Float) -> Int {
        guard value.isFinite else { return 0 }
        return Int((value * 100).rounded())
    }
}

// MARK: - Construction

extension FaultReadout {

    /// Per-fault readouts in catalog order (== `IssueWindow.probs` order ==
    /// `ISSUE_LABELS` order in `ml/ml/model.py`).
    ///
    /// Empty for an empty window array — legacy sessions stored none, and
    /// there is no honest reading to show for a clip that has none.
    ///
    /// A channel missing from *every* window is dropped rather than reported
    /// as zero. That cannot happen for data this app wrote (`SwimTCNRunner`
    /// rejects any output that isn't exactly `expectedLabelCount` long, and
    /// `AnalyzingView` would have trapped before storing it), but a stored
    /// session is external input and a fabricated 0% would be a lie.
    static func readouts(from windows: [IssueWindow]) -> [FaultReadout] {
        guard !windows.isEmpty else { return [] }

        let names = FeedbackEngine.issueNames
        var sums = [Float](repeating: 0, count: names.count)
        var peaks = [Float](repeating: 0, count: names.count)
        var seen = [Bool](repeating: false, count: names.count)

        for window in windows {
            for i in sums.indices where window.probs.indices.contains(i) {
                let p = window.probs[i]
                sums[i] += p
                peaks[i] = seen[i] ? max(peaks[i], p) : p
                seen[i] = true
            }
        }

        // Divide by the window count, not by a per-channel count: that is
        // what `AnalyzingView` divides by, and matching it is the whole
        // point (see the type comment).
        let divisor = Float(windows.count)

        return names.indices.compactMap { i -> FaultReadout? in
            guard seen[i],
                  let info = FeedbackEngine.displayInfo(for: names[i]) else { return nil }
            return FaultReadout(name: names[i],
                                displayName: info.display,
                                channel: i,
                                mean: sums[i] / divisor,
                                peak: peaks[i])
        }
    }

    /// Display order: strongest reading first.
    ///
    /// Because the bands are cut-points on the same value being sorted, one
    /// descending sort already groups them — flagged, then close, then clear
    /// — so the section's band headings are labels drawn across a single
    /// continuous ranking rather than a second, competing order the reader
    /// has to reconcile.
    ///
    /// Ties break to catalog order, which keeps left/right pairs in their
    /// familiar sequence and keeps the whole list deterministic.
    static func ranked(from windows: [IssueWindow]) -> [FaultReadout] {
        readouts(from: windows).sorted {
            $0.mean != $1.mean ? $0.mean > $1.mean : $0.channel < $1.channel
        }
    }
}
