import XCTest

/// Runs every bundled sample swim through the real pipeline on a physical
/// iPhone and records what the model found.
///
/// Vision pose extraction fails in the simulator (error 9 on every frame, on
/// the iOS 26 and 27 runtimes alike), so every other sample test stops short
/// of analysis. This suite is the other half: it only runs on hardware, and it
/// asserts that each clip reaches Results — the path App Review takes when it
/// taps "Try a sample swim" — rather than "Couldn't read this footage".
///
/// Each run prints one `DEVICE_SAMPLE` line per clip with the score and every
/// fault's readout, so a device run doubles as a record of the model's output
/// on real footage.
final class DeviceSampleAnalysisUITests: XCTestCase {

    /// Pose extraction, windowing and inference on a ~10-second clip. Generous
    /// because an older iPhone on a cold CoreML cache is the case that matters.
    private static let analysisTimeout: TimeInterval = 120

    override func setUpWithError() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Vision pose extraction only works on a physical device.")
        #endif
        continueAfterFailure = false
    }

    func testDeckClipReachesResults() throws {
        try analyze("sample_crawl_deck")
    }

    func testUnderwaterClipReachesResults() throws {
        try analyze("sample_crawl_underwater")
    }

    func testSprintClipReachesResults() throws {
        try analyze("sample_crawl_sprint")
    }

    // MARK: - Driving one sample

    private func analyze(_ clip: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenOnboarding", "YES", "-suppressWhatsNew",
                               "-seedFirstRun", "-openSamples"]
        app.launch()

        XCTAssertTrue(identified(app, "sampleSwimsScreen").waitForExistence(timeout: 15),
                      "the samples screen never opened", file: file, line: line)
        let row = identified(app, "sampleClipRow-\(clip)")
        XCTAssertTrue(scroll(app, to: row), "\(clip) never came into view", file: file, line: line)
        row.tap()

        let score = labelled(app, "Technique score")
        let failed = app.staticTexts["ANALYSIS FAILED"]
        let deadline = Date().addingTimeInterval(Self.analysisTimeout)
        while Date() < deadline, !score.exists, !failed.exists {
            _ = score.waitForExistence(timeout: 2)
        }

        if failed.exists {
            attach("\(clip)-failed")
            let reason = app.staticTexts.allElementsBoundByIndex
                .map(\.label).filter { !$0.isEmpty }.joined(separator: " | ")
            print("DEVICE_SAMPLE \(clip) FAILED: \(reason)")
            XCTFail("\(clip) was rejected on device: \(reason)", file: file, line: line)
            return
        }
        XCTAssertTrue(score.exists, "\(clip) never reached Results within "
                      + "\(Int(Self.analysisTimeout))s", file: file, line: line)
        attach("\(clip)-results-top")

        let readout = collectReadout(app)
        attach("\(clip)-results-readout")
        print("DEVICE_SAMPLE \(clip) | \(score.label) | \(readout.joined(separator: " | "))")
        XCTAssertEqual(readout.count, 10,
                       "expected all ten fault channels in the full readout, got \(readout.count)",
                       file: file, line: line)
    }

    /// Every full-readout row, in the order they come into view. Each row's
    /// accessibility label carries its fault, band and percentage.
    private func collectReadout(_ app: XCUIApplication) -> [String] {
        // Every band's label ends "... the N percent line." — anchoring on the
        // phrase keeps the issue timeline's summary out of the collection.
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "percent line"))
        var seen: [String] = []
        for _ in 0..<12 {
            for label in rows.allElementsBoundByIndex.map(\.label) where !seen.contains(label) {
                seen.append(label)
            }
            if seen.count >= 10 { break }
            app.swipeUp()
        }
        return seen
    }

    // MARK: - Helpers

    private func identified(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    private func labelled(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", text))
            .firstMatch
    }

    private func scroll(_ app: XCUIApplication, to target: XCUIElement) -> Bool {
        for _ in 0..<8 {
            if target.exists && target.isHittable { return true }
            app.swipeUp()
        }
        return target.exists && target.isHittable
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
