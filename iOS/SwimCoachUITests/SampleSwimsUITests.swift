import XCTest

/// The sample-swim screen, in the appearances and text sizes it actually
/// ships in.
///
/// Vision pose extraction does not work in the simulator, so nothing here
/// analyzes a clip — that end of the feature needs a device. What these tests
/// can hold, and do, is everything up to the tap: that all four rows render,
/// that the licence credit is on the screen the clips are on rather than
/// three taps away, and that neither of those survives only at the default
/// text size.
final class SampleSwimsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenOnboarding", "YES", "-suppressWhatsNew"] + args
        app.launch()
        return app
    }

    private func labelled(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", text))
            .firstMatch
    }

    private func scroll(_ app: XCUIApplication, to target: XCUIElement,
                        maxSwipes: Int = 8) -> Bool {
        for _ in 0..<maxSwipes {
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

    /// Every catalog row must reach the screen. A clip that is listed but did
    /// not ship renders inert rather than vanishing (`SampleClipCatalogTests`
    /// catches the shipping failure itself); this catches the list never
    /// drawing at all.
    private func assertEveryClipRowIsPresent(_ app: XCUIApplication,
                                             file: StaticString = #filePath,
                                             line: UInt = #line) {
        for name in ["sample_poolside", "sample_underwater_a",
                     "sample_underwater_b", "sample_underwater_c"] {
            let row = element(app, "sampleClipRow-\(name)")
            XCTAssertTrue(scroll(app, to: row),
                          "\(name) never came into view on the samples screen",
                          file: file, line: line)
        }
    }

    // MARK: - Light

    func testSampleSwimsListsEveryClipAndStatesBothHalvesOfTheDeal() {
        let app = launch(["-openSamples"])
        XCTAssertTrue(element(app, "sampleSwimsScreen").waitForExistence(timeout: 10),
                      "-openSamples did not present the sheet")

        // The pair that has to travel together: the numbers are real AND the
        // swim is not the user's. Either alone misleads.
        XCTAssertTrue(labelled(app, "Real numbers").exists,
                      "the screen stopped saying the analysis is genuine")
        XCTAssertTrue(labelled(app, "not saved").exists,
                      "the screen stopped saying the result stays out of history")

        // Captured before the scroll, so the attachment shows what a user
        // sees on arrival rather than wherever the search left the page.
        attach("samples-light-top")
        assertEveryClipRowIsPresent(app)
        attach("samples-light-clips")
    }

    /// CC BY 3.0 §4(c) is a shipping condition, not a nicety: the author, the
    /// work and the licence have to be visible to whoever sees the footage.
    /// If a later refactor quietly drops the credit block, this fails.
    func testFootageCreditNamesTheAuthorTheWorkAndTheLicence() {
        let app = launch(["-openSamples"])
        XCTAssertTrue(element(app, "sampleSwimsScreen").waitForExistence(timeout: 10))

        let credit = labelled(app, "koolkatkari")
        XCTAssertTrue(scroll(app, to: credit),
                      "the footage author is not credited anywhere on this screen")
        XCTAssertTrue(labelled(app, "Mary's Swim Boot Camp").exists,
                      "the credited work is missing from the attribution")
        XCTAssertTrue(labelled(app, "Creative Commons Attribution 3.0").exists,
                      "the licence is not named in the attribution")

        let link = labelled(app, "View the Creative Commons Attribution 3.0 licence")
        XCTAssertTrue(scroll(app, to: link),
                      "the licence link is not reachable")
        attach("samples-credit")
    }

    // MARK: - Dark

    func testSampleSwimsHoldsUpInTheDarkAppearance() {
        let app = launch(["-openSamples", "-UIUserInterfaceStyle", "Dark"])
        XCTAssertTrue(element(app, "sampleSwimsScreen").waitForExistence(timeout: 10))
        XCTAssertTrue(labelled(app, "Real numbers").exists)
        attach("samples-dark-top")
        assertEveryClipRowIsPresent(app)
        attach("samples-dark-clips")
    }

    // MARK: - Accessibility text sizes

    /// The screen carries a wrapping paragraph beside a fixed-width still, a
    /// two-line terms card and a tracked all-caps link — three shapes that
    /// each fail differently under large type. The rows stack their
    /// thumbnails above their copy at accessibility sizes; this asserts the
    /// result is still reachable rather than pushed off the edge.
    func testSampleSwimsSurvivesAccessibilityTextSizes() {
        let app = launch(["-openSamples",
                          "-UIPreferredContentSizeCategoryName",
                          "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(element(app, "sampleSwimsScreen").waitForExistence(timeout: 10))
        attach("samples-ax-top")

        assertEveryClipRowIsPresent(app, line: #line)

        // The last thing on the page, at the largest type the app renders:
        // if anything clips, it clips here.
        let link = labelled(app, "View the Creative Commons Attribution 3.0 licence")
        XCTAssertTrue(scroll(app, to: link, maxSwipes: 20),
                      "the licence credit is unreachable at accessibility text sizes")
        attach("samples-ax-credit")
    }

    // MARK: - Entry points on Home

    /// Both entry points, in the state each exists for. The index row is
    /// permanent; the first-run footer only exists while there is nothing
    /// else on the page to look at.
    func testHomeOffersSamplesPermanentlyAndInTheEmptyState() {
        // The store survives between launches, so "don't seed" is not the
        // same as "empty" — a previous test's fixture would still be here.
        let empty = launch(["-seedFirstRun"])
        XCTAssertTrue(empty.staticTexts["SwimCoach"].waitForExistence(timeout: 10))
        XCTAssertTrue(empty.staticTexts["Film your first swim"].exists,
                      "expected the zero-session state")
        XCTAssertTrue(empty.buttons["Try a sample swim"].exists,
                      "the empty state has no way to see the app work")
        attach("home-empty-with-sample")

        let row = labelled(empty, "Sample swims")
        XCTAssertTrue(scroll(empty, to: row),
                      "the permanent sample-swims row is missing from Home")
        empty.terminate()

        // With sessions saved the first-run card is gone — the index row must
        // not go with it, or samples become findable exactly once.
        let seeded = launch(["-seedTrainingLog"])
        XCTAssertTrue(seeded.staticTexts["SwimCoach"].waitForExistence(timeout: 10))
        XCTAssertFalse(seeded.staticTexts["Film your first swim"].exists,
                       "expected the seeded, non-empty state")
        XCTAssertTrue(scroll(seeded, to: labelled(seeded, "Sample swims")),
                      "the sample-swims row disappeared once sessions existed")
        attach("home-seeded-with-sample")
    }

    /// The route, as far as the simulator can take it: the sheet closes, the
    /// stack pushes, and the clip lands in `AnalyzingView` — the same screen
    /// a filmed swim gets, not a bespoke sample player.
    ///
    /// It then fails, and that failure is the assertion. Vision returns error
    /// 9 for every frame in the simulator, so pose extraction finds no
    /// swimmer and the run stops at `noSwimmerDetected` — the ordinary
    /// footage-rejection state, stamped NO READ.
    ///
    /// That is a stronger result than catching the ANALYZING masthead would
    /// have been, and it is why this test does not wait for one: reaching a
    /// *pose-extraction* failure proves the clip went through
    /// `runAnalysis()`. The bundled demo cartoon's `runDemoAnalysis()` path
    /// fabricates a fixed result without touching Vision and always reaches
    /// Results. A sample that had been mistaken for the demo clip, or given a
    /// shortcut of its own, could not fail this way.
    ///
    /// What the simulator cannot show is a run that succeeds. Real scores,
    /// real faults, and the no-save rule taking effect on a result that
    /// actually exists all need a device.
    func testTappingASampleRunsTheRealPipelineAndNotTheDemoShortcut() {
        let app = launch(["-seedFirstRun", "-openSamples"])
        XCTAssertTrue(element(app, "sampleSwimsScreen").waitForExistence(timeout: 10))

        let row = element(app, "sampleClipRow-sample_poolside")
        XCTAssertTrue(scroll(app, to: row))
        row.tap()

        XCTAssertTrue(app.staticTexts["ANALYSIS FAILED"].waitForExistence(timeout: 30),
                      "a sample never reached the app's ordinary analysis screen")
        XCTAssertTrue(labelled(app, "No horizontal swimmer detected").exists,
                      """
                      the run did not stop in pose extraction, so this clip did not \
                      go through the real Vision path — check that it has not been \
                      routed to runDemoAnalysis()
                      """)
        attach("samples-analyzing-simulator")

        // And it did not quietly bank the attempt: back on Home the app is
        // still in its zero-session state. (The escape hatch is addressed by
        // its accessibility label, not its rendered "BACK TO HOME" caps.)
        app.buttons["Go back to Home"].tap()
        XCTAssertTrue(app.staticTexts["Film your first swim"].waitForExistence(timeout: 10),
                      "a sample run left something behind in the user's history")
    }
}
