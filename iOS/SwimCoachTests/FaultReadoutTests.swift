import XCTest
@testable import SwimCoach

/// `FaultReadout` recovers the seven-or-so channels the Results screen has
/// always thrown away. Its whole claim to be showable is that the numbers it
/// prints are the numbers `FeedbackEngine.decode` was actually given — not an
/// approximation of them — so the reconstruction is pinned first and
/// hardest, then the banding, then the edges.
final class FaultReadoutTests: XCTestCase {

    private let labelCount = FeedbackEngine.issueNames.count

    private func window(_ start: Double, _ probs: [Float]) -> IssueWindow {
        IssueWindow(start: start, end: start + 3, probs: probs)
    }

    /// Fills every channel so a fixture never accidentally tests a short row.
    private func flat(_ value: Float, _ overrides: [Int: Float] = [:]) -> [Float] {
        var probs = [Float](repeating: value, count: labelCount)
        for (i, v) in overrides { probs[i] = v }
        return probs
    }

    // MARK: - Reconstruction (the load-bearing claim)

    /// Replays `AnalyzingView`'s own accumulation and asserts BIT equality —
    /// not `accuracy:`. A tolerance here would pass even if this type summed
    /// in `Double` or divided per channel, which is exactly the drift that
    /// would let the read-out contradict the Issues section on a boundary
    /// reading. Float addition is neither associative nor commutative, so
    /// "same numbers" is only true while the order and type match.
    func testMeanIsBitIdenticalToTheVectorDecodeReceives() {
        let windows = [
            window(0.0, [0.11, 0.37, 0.52, 0.09, 0.61, 0.44, 0.55, 0.30, 0.35, 0.17]),
            window(1.5, [0.23, 0.41, 0.63, 0.13, 0.58, 0.46, 0.85, 0.42, 0.50, 0.19]),
            window(3.0, [0.19, 0.39, 0.71, 0.11, 0.62, 0.43, 0.95, 0.46, 0.60, 0.13]),
            window(4.5, [0.27, 0.35, 0.54, 0.15, 0.59, 0.41, 0.90, 0.38, 0.55, 0.21]),
        ]

        // Verbatim from AnalyzingView.swift — the pipeline's own arithmetic.
        var probSum = [Float](repeating: 0, count: labelCount)
        for w in windows {
            for i in probSum.indices { probSum[i] += w.probs[i] }
        }
        let pipelineProbs = probSum.map { $0 / Float(windows.count) }

        let readouts = FaultReadout.readouts(from: windows)
        XCTAssertEqual(readouts.count, labelCount)
        for readout in readouts {
            XCTAssertEqual(
                readout.mean, pipelineProbs[readout.channel],
                """
                Channel \(readout.channel) (\(readout.name)) reconstructed \
                \(readout.mean) but decode was handed \
                \(pipelineProbs[readout.channel]). The read-out is only \
                showable because these are the same Float — see the exactness \
                note on FaultReadout.
                """)
        }
    }

    /// The consequence of the above: the flagged band and `decode`'s output
    /// are the same set of faults, for readings deliberately parked on and
    /// around the bar. If these ever diverge, Results shows a fault under
    /// "Flagged" that the Issues section above does not list.
    func testFlaggedBandMatchesDecodeExactly() {
        let bar = FeedbackEngine.threshold
        let windows = [
            window(0.0, flat(0.13, [0: bar, 2: 0.9, 4: bar - 0.01, 6: 0.46, 8: 0.30])),
            window(1.5, flat(0.13, [0: bar, 2: 0.9, 4: bar - 0.01, 6: 0.46, 8: 0.30])),
        ]
        let readouts = FaultReadout.readouts(from: windows)

        let flagged = Set(readouts.filter { $0.band == .flagged }.map(\.name))
        let decoded = Set(FeedbackEngine
            .decode(probabilities: readouts.map(\.mean))
            .map(\.name))

        XCTAssertEqual(flagged, decoded)
        XCTAssertEqual(flagged, ["left_elbow_overextension", "left_elbow_collapse", "body_sag"])
    }

    // MARK: - Banding

    /// The exactly-at-threshold boundary. `decode` reports at `>=`, so the
    /// read-out must flag at `>=` too — a fault reading precisely 0.45 is
    /// detected, and must never appear under "close, not flagged".
    func testExactlyAtThresholdIsFlaggedNotClose() {
        XCTAssertEqual(FaultReadout.band(for: FeedbackEngine.threshold), .flagged)
        XCTAssertEqual(FaultReadout.band(for: FeedbackEngine.threshold.nextDown), .close)

        // …and end to end, through the mean, with a divisor that returns the
        // value untouched.
        let windows = [window(0.0, flat(0.13, [6: FeedbackEngine.threshold]))]
        let sag = try? XCTUnwrap(FaultReadout.readouts(from: windows)
            .first { $0.name == "body_sag" })
        XCTAssertEqual(sag?.mean, FeedbackEngine.threshold)
        XCTAssertEqual(sag?.band, .flagged)
        XCTAssertFalse(FeedbackEngine.decode(probabilities: [Float](repeating: 0, count: 6)
                                             + [FeedbackEngine.threshold]).isEmpty)
    }

    func testCloseBandFloorIsInclusiveAndClearBelowIt() {
        XCTAssertEqual(FaultReadout.band(for: FaultReadout.closeFloor), .close)
        XCTAssertEqual(FaultReadout.band(for: FaultReadout.closeFloor.nextDown), .clear)
        XCTAssertEqual(FaultReadout.band(for: 0), .clear)
        XCTAssertEqual(FaultReadout.band(for: 1), .flagged)
    }

    /// The band floor is derived from the threshold, never typed twice — so
    /// a threshold change moves the band with it instead of stranding it.
    func testCloseFloorTracksTheThreshold() {
        XCTAssertEqual(FaultReadout.flagBar, FeedbackEngine.threshold)
        XCTAssertEqual(FaultReadout.closeFloor,
                       FeedbackEngine.threshold * FaultReadout.closeFraction)
        XCTAssertLessThan(FaultReadout.closeFloor, FaultReadout.flagBar)
        // The copy interpolates these; they must round to the stated cuts.
        XCTAssertEqual(FaultReadout.percent(FaultReadout.flagBar), 45)
        XCTAssertEqual(FaultReadout.percent(FaultReadout.closeFloor), 30)
    }

    // MARK: - Shape and order

    func testReadoutsAreInCatalogOrderAndCoverEveryChannel() {
        let windows = [window(0.0, flat(0.2)), window(1.5, flat(0.4))]
        let readouts = FaultReadout.readouts(from: windows)

        XCTAssertEqual(readouts.map(\.name), FeedbackEngine.issueNames)
        XCTAssertEqual(readouts.map(\.channel), Array(0..<labelCount))
        for readout in readouts {
            XCTAssertEqual(FeedbackEngine.labelIndex(of: readout.name), readout.channel)
            XCTAssertFalse(readout.displayName.isEmpty)
        }
    }

    func testRankedSortsByStrengthDescendingAndGroupsBandsContiguously() {
        let windows = [
            window(0.0, [0.13, 0.90, 0.31, 0.13, 0.46, 0.13, 0.80, 0.39, 0.13, 0.20]),
            window(1.5, [0.13, 0.90, 0.31, 0.13, 0.46, 0.13, 0.80, 0.39, 0.13, 0.20]),
        ]
        let ranked = FaultReadout.ranked(from: windows)

        XCTAssertEqual(ranked.count, labelCount)
        for (a, b) in zip(ranked, ranked.dropFirst()) {
            XCTAssertGreaterThanOrEqual(a.mean, b.mean)
            // Bands are cut-points on the value being sorted, so one
            // descending sort must already group them.
            XCTAssertLessThanOrEqual(a.band.rawValue, b.band.rawValue)
        }
        XCTAssertEqual(ranked.first?.name, "right_elbow_overextension")   // 0.90
        XCTAssertEqual(ranked.map(\.band).prefix(3),
                       [.flagged, .flagged, .flagged])                    // .90 .80 .46
    }

    /// Ties resolve to catalog order, so the list is stable across renders
    /// and left/right pairs keep their familiar sequence.
    func testRankedBreaksTiesByCatalogOrder() {
        let ranked = FaultReadout.ranked(from: [window(0.0, flat(0.2))])
        XCTAssertEqual(ranked.map(\.channel), Array(0..<labelCount))
        XCTAssertEqual(ranked.map(\.name), FeedbackEngine.issueNames)
    }

    // MARK: - Peak

    func testPeakIsTheStrongestSingleWindowAndAgreesWithPeakWindow() {
        let windows = [
            window(0.0, flat(0.13, [6: 0.30])),
            window(1.5, flat(0.13, [6: 0.95])),
            window(3.0, flat(0.13, [6: 0.60])),
        ]
        let sag = FaultReadout.readouts(from: windows).first { $0.name == "body_sag" }
        XCTAssertEqual(sag?.peak, 0.95)
        XCTAssertEqual(sag?.peak, windows.peakWindow(labelIndex: 6)?.probs[6])
        XCTAssertGreaterThan(try XCTUnwrap(sag).peak, try XCTUnwrap(sag).mean)
        XCTAssertTrue(try XCTUnwrap(sag).showsPeak)
    }

    /// A fault that peaked over the bar while its clip average stayed under
    /// is still NOT a detection — the case the section's copy has to survive.
    func testPeakAboveBarWithMeanBelowStaysInTheCloseBand() {
        let windows = [
            window(0.0, flat(0.13, [7: 0.30])),
            window(1.5, flat(0.13, [7: 0.42])),
            window(3.0, flat(0.13, [7: 0.46])),   // over the bar, this window
            window(4.5, flat(0.13, [7: 0.38])),
        ]
        let asymmetry = try? XCTUnwrap(FaultReadout.readouts(from: windows)
            .first { $0.name == "stroke_asymmetry" })
        XCTAssertEqual(asymmetry?.band, .close)
        XCTAssertEqual(asymmetry?.meanPercent, 39)
        XCTAssertEqual(asymmetry?.peakPercent, 46)
        XCTAssertGreaterThan(try XCTUnwrap(asymmetry).peak, FeedbackEngine.threshold)
        // And decode agrees it is not an issue.
        XCTAssertTrue(FeedbackEngine
            .decode(probabilities: FaultReadout.readouts(from: windows).map(\.mean))
            .filter { $0.name == "stroke_asymmetry" }.isEmpty)
    }

    /// A flat fault says everything with one number; the row suppresses the
    /// redundant second one.
    func testFlatFaultHidesItsPeak() {
        let windows = [window(0.0, flat(0.24)), window(1.5, flat(0.24))]
        for readout in FaultReadout.readouts(from: windows) {
            XCTAssertEqual(readout.peak, readout.mean)
            XCTAssertFalse(readout.showsPeak)
        }
    }

    // MARK: - Edges

    /// Legacy sessions stored no windows. Nothing to show, and nothing
    /// fabricated: the section keys its whole visibility off this being empty.
    func testEmptyWindowArrayYieldsNoReadouts() {
        XCTAssertTrue(FaultReadout.readouts(from: []).isEmpty)
        XCTAssertTrue(FaultReadout.ranked(from: []).isEmpty)
    }

    /// The legacy shape itself: a session saved before windows were stored
    /// has `issueWindows == nil`, which the section coalesces to `[]` and
    /// then hides on. A zeroed ten-row table would be an invention.
    func testSessionWithNoStoredWindowsYieldsNothingToShow() {
        XCTAssertNil(AnalysisResult.demoEarlier.issueWindows)
        XCTAssertTrue(FaultReadout.ranked(from: AnalysisResult.demoEarlier.issueWindows ?? []).isEmpty)
    }

    /// A row written before windows existed — the literal stored shape, with
    /// no `issueWindows` key at all — still decodes, still yields nothing to
    /// show, and re-encodes without growing the key back. This section is the
    /// first reader of that field, so its degradation path is pinned against
    /// the codec rather than against a fixture that happens to be nil.
    func testLegacyRowWithNoWindowsKeyDecodesAndDegradesSilently() throws {
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(AnalysisResult.demo)) as? [String: Any])
        json.removeValue(forKey: "issueWindows")
        json.removeValue(forKey: "keypointFrames")
        json.removeValue(forKey: "durationSeconds")

        let legacy = try JSONDecoder().decode(
            AnalysisResult.self,
            from: try JSONSerialization.data(withJSONObject: json))

        XCTAssertNil(legacy.issueWindows)
        XCTAssertTrue(FaultReadout.ranked(from: legacy.issueWindows ?? []).isEmpty)
        XCTAssertEqual(legacy.issues.map(\.name), AnalysisResult.demo.issues.map(\.name),
                       "the rest of a legacy row must survive the missing key")

        // `encodeIfPresent` — a nil field must not reappear as null on rewrite.
        let rewritten = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(legacy)) as? [String: Any])
        XCTAssertNil(rewritten["issueWindows"])
    }

    /// The windows themselves round-trip exactly. Everything this section
    /// prints is derived from them, so a lossy codec would show one set of
    /// numbers on a fresh analysis and another after a relaunch.
    func testStoredWindowsRoundTripExactlyThroughTheCodec() throws {
        let original = try XCTUnwrap(AnalysisResult.demo.issueWindows)
        let decoded = try JSONDecoder().decode(
            AnalysisResult.self, from: try JSONEncoder().encode(AnalysisResult.demo))

        XCTAssertEqual(decoded.issueWindows, original)
        XCTAssertEqual(FaultReadout.ranked(from: try XCTUnwrap(decoded.issueWindows)),
                       FaultReadout.ranked(from: original))
    }

    /// A single window is a real case — a clip barely over three seconds
    /// produces exactly one. Mean must equal that window, not divide by zero
    /// or by a hardcoded count.
    func testSingleWindowMeanEqualsThatWindow() {
        let probs: [Float] = [0.13, 0.22, 0.45, 0.31, 0.87, 0.13, 0.66, 0.44, 0.30, 0.29]
        let readouts = FaultReadout.readouts(from: [window(0.0, probs)])

        XCTAssertEqual(readouts.count, labelCount)
        XCTAssertEqual(readouts.map(\.mean), probs)
        XCTAssertEqual(readouts.map(\.peak), probs)
        XCTAssertEqual(readouts.map(\.band),
                       [.clear, .clear, .flagged, .close, .flagged,
                        .clear, .flagged, .close, .close, .clear])
        for readout in readouts { XCTAssertFalse(readout.showsPeak) }
    }

    /// A short `probs` row can only arrive from stored data this app did not
    /// write. Report what is there; never invent a 0% for what is not.
    func testChannelsMissingFromEveryWindowAreDroppedNotZeroed() {
        let short = [Float](repeating: 0.5, count: 4)
        let readouts = FaultReadout.readouts(from: [window(0.0, short)])

        XCTAssertEqual(readouts.count, 4)
        XCTAssertEqual(readouts.map(\.channel), [0, 1, 2, 3])
        XCTAssertEqual(readouts.map(\.name), Array(FeedbackEngine.issueNames.prefix(4)))
    }

    /// Extra channels beyond the catalog are ignored the same way `decode`
    /// ignores them — the catalog, not the payload, decides what exists.
    func testExtraChannelsBeyondTheCatalogAreIgnored() {
        let long = [Float](repeating: 0.5, count: labelCount + 5)
        XCTAssertEqual(FaultReadout.readouts(from: [window(0.0, long)]).count, labelCount)
    }

    // MARK: - Percent rounding

    func testPercentRoundingIsSharedAndTotal() {
        XCTAssertEqual(FaultReadout.percent(0), 0)
        XCTAssertEqual(FaultReadout.percent(1), 100)
        XCTAssertEqual(FaultReadout.percent(0.13), 13)
        XCTAssertEqual(FaultReadout.percent(0.8125), 81)
        XCTAssertEqual(FaultReadout.percent(.nan), 0)
        XCTAssertEqual(FaultReadout.percent(.infinity), 0)
    }

    // MARK: - Demo fixture

    /// `-demoResults` is the only way to see this section without a device,
    /// so the fixture has to keep exercising all three bands — including the
    /// close band, which is the part of the section that can be misread.
    func testDemoFixtureCoversAllThreeBands() throws {
        let windows = try XCTUnwrap(AnalysisResult.demo.issueWindows)
        let ranked = FaultReadout.ranked(from: windows)

        XCTAssertEqual(ranked.filter { $0.band == .flagged }.count, 3)
        XCTAssertEqual(ranked.filter { $0.band == .close }.count, 2)
        XCTAssertEqual(ranked.filter { $0.band == .clear }.count, 5)

        // The flagged band is exactly what the fixture's issues list claims.
        XCTAssertEqual(Set(ranked.filter { $0.band == .flagged }.map(\.name)),
                       Set(AnalysisResult.demo.issues.map(\.name)))

        // …and the close band still contains the peaked-but-not-flagged case.
        let asymmetry = try XCTUnwrap(ranked.first { $0.name == "stroke_asymmetry" })
        XCTAssertEqual(asymmetry.band, .close)
        XCTAssertGreaterThan(asymmetry.peak, FeedbackEngine.threshold)
    }

    /// `SwimTCN.forward()` clamps its logits to ±1.9, so a real probability is
    /// bounded to (0.13, 0.87). The read-out is the first surface that prints
    /// these as numbers rather than only threshold-testing them, so a fixture
    /// reading 95% — which the model cannot emit — would put a figure on
    /// screen that no clip could ever produce.
    func testDemoFixtureStaysInsideTheModelsOutputRange() throws {
        let windows = try XCTUnwrap(AnalysisResult.demo.issueWindows)
        for window in windows {
            for (channel, p) in window.probs.enumerated() {
                XCTAssertGreaterThan(p, 0.13, "channel \(channel) at t=\(window.start) is under "
                                     + "the sigmoid floor the ±1.9 logit clamp imposes")
                XCTAssertLessThan(p, 0.87, "channel \(channel) at t=\(window.start) is over "
                                  + "the sigmoid ceiling the ±1.9 logit clamp imposes")
            }
        }
    }

    /// The three faults the fixture's `issues` list names are exactly the
    /// three whose windows cross the bar, and no edit to the window values may
    /// quietly add or drop one — the flagged band is rendered from the windows
    /// while the Issues section above is rendered from `issues`.
    func testDemoFixtureWindowsDecodeToItsDeclaredIssues() throws {
        let windows = try XCTUnwrap(AnalysisResult.demo.issueWindows)
        let means = FaultReadout.readouts(from: windows).map(\.mean)
        XCTAssertEqual(Set(FeedbackEngine.decode(probabilities: means).map(\.name)),
                       Set(AnalysisResult.demo.issues.map(\.name)))
    }
}
