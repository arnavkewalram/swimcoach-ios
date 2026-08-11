import XCTest

/// Address a view by accessibility identifier without pinning its element
/// type. SwiftUI decides whether a grouped element surfaces as a button, a
/// static text or a plain container — that choice is an implementation detail
/// of the accessibility tree, not something a route test should assert on.
func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
}

/// Launch-flow smoke tests: every major route must render its landmark
/// content. These catch routing crashes and blank screens that unit
/// tests structurally cannot see. Simulator-safe — all routes below work
/// without Vision.
final class SmokeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // UserDefaults launch-argument override skips onboarding
        app.launchArguments = ["-hasSeenOnboarding", "YES", "-suppressWhatsNew"] + args
        app.launch()
        return app
    }

    func testHomeRendersMastheadAndCTA() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["SwimCoach"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Analyze a swim"].exists)
        XCTAssertTrue(app.staticTexts["Import a video"].exists)
    }

    func testDemoResultsRendersScorePanel() {
        let app = launch(["-demoResults"])
        XCTAssertTrue(app.staticTexts["TECHNIQUE SCORE"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["ISSUES DETECTED"].exists)
    }

    /// The full read-out reports channels the Issues section never mentions,
    /// so "it built" proves nothing — the rows have to be in the tree. The
    /// close band is asserted hardest because it is the band that can be
    /// misread: a row reading under the bar must never surface as a detection,
    /// and must never speak a severity, which is the app's word for one.
    func testDemoResultsRendersFullReadoutIncludingTheCloseBand() {
        let app = launch(["-demoResults"])
        XCTAssertTrue(app.staticTexts["TECHNIQUE SCORE"].waitForExistence(timeout: 10))

        let header = app.staticTexts["FULL READ-OUT"]
        XCTAssertTrue(scroll(app, to: header, maxSwipes: 14), "Full read-out never came into view")
        XCTAssertTrue(app.staticTexts["FLAGGED · 3"].exists)
        XCTAssertTrue(app.staticTexts["CLOSE, NOT FLAGGED · 2"].exists)
        attach(XCUIScreen.main.screenshot(), "full-readout-flagged-and-close")

        // A flagged row is a finding, and says so in the Issues section's own
        // vocabulary — the chip word is folded into the row's label.
        let sag = labelled(app, "Body Sag, flagged")
        XCTAssertTrue(scroll(app, to: sag, maxSwipes: 14), "The flagged band never came into view")
        XCTAssertTrue(sag.label.contains("major severity"),
                      "A finding must carry its severity: \(sag.label)")

        // Every scored fault is present, not just the three that fired.
        let asymmetry = labelled(app, "Stroke Asymmetry, close")
        XCTAssertTrue(scroll(app, to: asymmetry, maxSwipes: 14),
                      "A sub-threshold fault must still be listed")
        XCTAssertTrue(asymmetry.label.contains("close but not flagged"),
                      "Close reading spoke as: \(asymmetry.label)")
        XCTAssertTrue(asymmetry.label.contains("Not a detected issue"),
                      "A near miss must say it is not a detection: \(asymmetry.label)")
        for word in ["major severity", "moderate severity", "minor severity"] {
            XCTAssertFalse(asymmetry.label.contains(word),
                           "A near miss wore a severity — the app's mark for a "
                           + "finding: \(asymmetry.label)")
        }

        let clear = labelled(app, "Excessive Kick Rate, clear")
        XCTAssertTrue(scroll(app, to: clear, maxSwipes: 14), "A clean fault must still be listed")
        XCTAssertTrue(clear.label.contains("clear"), "Clear reading spoke as: \(clear.label)")
        attach(XCUIScreen.main.screenshot(), "full-readout-clear")
    }

    /// Name + mark + figure on one line is the densest row in the app, and at
    /// an accessibility size it has to reflow downward rather than truncate.
    ///
    /// Measured from the rows' frames rather than by scrolling to them: the
    /// section runs several screens long at these sizes, and a swipe-until-
    /// visible walk is a coin toss about overshoot, not a layout assertion.
    /// The read-out lives in a `ScrollView`, so every row is in the tree with a
    /// real frame whether or not it is on screen.
    ///
    /// Two things are pinned. Every row stays inside the window horizontally —
    /// a row that failed to reflow would push its figure past the edge. And
    /// every row is TALLER than at the default size, which is what proves the
    /// override took: an accessibility run that silently rendered at the
    /// default size would satisfy every other assertion here without having
    /// tested anything. (That is not hypothetical — configuring this through
    /// `launchEnvironment["UIPreferredContentSizeCategoryName"]` does exactly
    /// that. The UserDefaults-override form below is the one that applies.)
    func testFullReadoutSurvivesAccessibilityType() {
        let readoutRows = { (app: XCUIApplication) -> [XCUIElement] in
            // Only the read-out's own rows say this — one phrase, ten rows.
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", "percent line"))
                .allElementsBoundByIndex
        }

        let baseline = launch(["-demoResults"])
        XCTAssertTrue(baseline.staticTexts["TECHNIQUE SCORE"].waitForExistence(timeout: 10))
        let defaultHeights = readoutRows(baseline).map(\.frame.height)
        XCTAssertEqual(defaultHeights.count, 10,
                       "expected one row per scored fault at the default size")
        baseline.terminate()

        let app = launch(["-UIPreferredContentSizeCategoryName",
                          "UICTContentSizeCategoryAccessibilityL",
                          "-demoResults"])
        XCTAssertTrue(app.staticTexts["TECHNIQUE SCORE"].waitForExistence(timeout: 10))

        let rows = readoutRows(app)
        XCTAssertEqual(rows.count, 10, "expected one row per scored fault at accessibility type")

        let window = app.windows.firstMatch.frame
        for (row, defaultHeight) in zip(rows, defaultHeights) {
            XCTAssertGreaterThanOrEqual(row.frame.minX, window.minX,
                                        "row overflows the window: \(row.label)")
            XCTAssertLessThanOrEqual(row.frame.maxX, window.maxX,
                                     "row overflows the window: \(row.label)")
            XCTAssertGreaterThan(
                row.frame.height, defaultHeight,
                """
                \(row.label) is \(row.frame.height)pt at AccessibilityL and \
                \(defaultHeight)pt at the default size. Either the row truncated \
                instead of reflowing, or the content-size override never applied \
                and this test measured the default size twice.
                """)
        }

        // Deliberately not scrolled to: at these sizes the section runs several
        // screens down, and swiping until it lands is a race with overshoot,
        // not evidence. The frames above are the assertion; this is only a
        // reviewable confirmation that the run really was at an AX size.
        attach(XCUIScreen.main.screenshot(), "results-at-accessibility-large")
    }

    private func attach(_ screenshot: XCUIScreenshot, _ name: String) {
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testSeededHistoryRendersChartsAndSessions() {
        let app = launch(["-seedTrainingLog", "-openHistory"])
        XCTAssertTrue(app.staticTexts["SCORE TREND"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["SESSIONS"].exists)
        XCTAssertTrue(app.staticTexts["Threshold Tuesday"].exists)
    }

    func testDrillsRendersLibrary() {
        let app = launch(["-openDrills"])
        XCTAssertTrue(app.staticTexts["Fingertip Drag"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Pull-Buoy Pull"].exists)
    }

    /// The drill read-out speaks in two registers and they must not collapse
    /// into one: a measured verdict states itself as a chip, a refusal to
    /// answer states itself as prose. They used to render byte-identically,
    /// so `testDrillsRendersLibrary` — which only proves the cards load —
    /// would have watched the distinction disappear without a word.
    ///
    /// Both are asserted from the seeded fixture, which lands one of each on
    /// a known card, and the screenshot is attached so the visual difference
    /// is reviewable at whatever text size the run used.
    func testDrillReadoutKeepsVerdictsAndRefusalsInDifferentRegisters() {
        let app = launch(["-seedDrillPractice", "-openDrills"])
        XCTAssertTrue(app.staticTexts["Fingertip Drag"].waitForExistence(timeout: 10))

        // Card 01 has never been marked done: a refusal, set as prose.
        XCTAssertTrue(labelled(app, "Not tracked yet").exists,
                      "the refusal register vanished from the never-practised card")

        // Card 03's faults advanced after the first tap: a verdict, in a chip.
        let verdict = labelled(app, "Showing up more")
        XCTAssertTrue(scroll(app, to: verdict, maxSwipes: 12),
                      "no measured verdict ever came into view")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "drill-verdict-chip"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Match on label content rather than element type: the drill card
    /// combines its children, so the read-out's words arrive folded into the
    /// card's own label rather than as free-standing static text.
    private func labelled(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", text))
            .firstMatch
    }

    func testAboutRendersVersionAndPrivacy() {
        let app = launch(["-openAbout"])
        XCTAssertTrue(app.staticTexts["PRIVACY"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["VIEW LICENSE"].exists
                      || app.staticTexts["VIEW LICENSE"].exists)
    }

    /// The recovery list for clips the store adopted but no session claimed.
    /// Before this route existed the launch sweep deleted them unseen, so a
    /// blank screen here is the bug coming back.
    func testUnfinishedTakesRendersRecoveryList() {
        let app = launch(["-seedUnfinishedTakes", "-openTakes"])
        let header = element(app, "unfinishedTakesHeader")
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(header.label.contains("2 WAITING"))
        XCTAssertTrue(app.buttons["Delete all unfinished takes"].exists)
    }

    /// Home offers the way in, the takes survive the relaunch that used to
    /// destroy them, and the surface disappears once nothing is waiting.
    func testTakesSurviveRelaunchAndHomeSurfaceClearsWhenEmpty() {
        let seeded = launch(["-seedUnfinishedTakes"])
        XCTAssertTrue(element(seeded, "unfinishedTakesStrip").waitForExistence(timeout: 10))
        seeded.terminate()

        // Fresh launch, no reseed: the launch sweep must have left them alone.
        let app = launch(["-openTakes"])
        let header = element(app, "unfinishedTakesHeader")
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(header.label.contains("2 WAITING"),
                      "Unfinished takes must survive a relaunch, not be pruned")

        app.buttons["Delete all unfinished takes"].tap()
        app.buttons["Delete 2 takes"].tap()
        XCTAssertTrue(element(app, "unfinishedTakesAllClear").waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["SwimCoach"].waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "unfinishedTakesStrip").exists,
                       "Zero takes must leave no empty state behind on Home")
    }

    /// Both training-log exports build their file off the main thread, so
    /// each row has to travel prepare → preparing → share on its own. A row
    /// still reading "PREPARE" here is the async hand-off never coming back
    /// — the failure mode a synchronous build could not have.
    func testAboutExportsReachShareReadyState() {
        let app = launch(["-seedTrainingLog", "-openAbout"])
        XCTAssertTrue(app.staticTexts["PRIVACY"].waitForExistence(timeout: 10))

        let prepareArchive = app.buttons["PREPARE JSON ARCHIVE"]
        XCTAssertTrue(scroll(app, to: prepareArchive), "Your-data section never came into view")
        prepareArchive.tap()
        XCTAssertTrue(app.buttons["EXPORT JSON ARCHIVE"].waitForExistence(timeout: 10),
                      "JSON archive never reached its share-ready state")

        let prepareCSV = app.buttons["PREPARE CSV SPREADSHEET"]
        XCTAssertTrue(scroll(app, to: prepareCSV))
        prepareCSV.tap()
        XCTAssertTrue(app.buttons["EXPORT CSV SPREADSHEET"].waitForExistence(timeout: 10),
                      "CSV spreadsheet never reached its share-ready state")
    }

    /// Swipe until `target` is on screen — About is a scroll view and the
    /// Your-data section sits below the fold.
    private func scroll(_ app: XCUIApplication, to target: XCUIElement,
                        maxSwipes: Int = 6) -> Bool {
        for _ in 0..<maxSwipes {
            if target.exists && target.isHittable { return true }
            app.swipeUp()
        }
        return target.exists && target.isHittable
    }

    func testDemoCompareRendersPanels() {
        let app = launch(["-demoCompare"])
        XCTAssertTrue(app.staticTexts["EARLIER"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["LATER"].exists)
    }

    /// Review's clip band is a `ZStack` of `Color.black` and a
    /// `UIViewRepresentable`, neither of which is an accessibility element —
    /// so its `.accessibilityLabel` reads like a label with nothing to
    /// attach to once the player replaces the loading spinner. This test was
    /// written to catch that and does not: it passes against the pre-fix code
    /// as well, because SwiftUI synthesises an element for a labelled view
    /// that has no accessible children. Kept as the regression pin the
    /// reasoning deserved — the band must stay reachable however it is built.
    func testReviewClipBandIsReachableByVoiceOver() {
        let app = launch(["-demoReview"])
        XCTAssertTrue(app.staticTexts["Check the\nframing"].waitForExistence(timeout: 10)
                      || app.descendants(matching: .any)
                          .matching(NSPredicate(format: "label CONTAINS 'Check the framing'"))
                          .firstMatch.waitForExistence(timeout: 10))

        let band = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Preview of the clip you just recorded")
        ).firstMatch
        XCTAssertTrue(band.waitForExistence(timeout: 10),
                      "The clip band must publish an accessibility element of its own")

        // The scrubber's own element is the precedent the band now follows.
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Clip position"))
            .firstMatch.exists)
    }

    /// All three framing rules have to be on screen at rest at the largest
    /// type size the app allows — the checklist is the reason this screen
    /// exists, and it used to slide under the action bar with item 02 sliced
    /// mid-glyph. Fails against the pre-fix build ("not on screen at rest:
    /// One lap at a normal pace").
    func testReviewChecklistSurvivesAccessibilityType() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenOnboarding", "YES", "-suppressWhatsNew", "-demoReview"]
        app.launchEnvironment["UIPreferredContentSizeCategoryName"] =
            "UICTContentSizeCategoryAccessibilityM"
        app.launch()

        let rules = ["Side-on, camera at water level",
                     "Full body above the waterline",
                     "One lap at a normal pace"]
        for rule in rules {
            XCTAssertTrue(app.staticTexts[rule].waitForExistence(timeout: 10),
                          "missing from the accessibility tree: \(rule)")
        }

        // 844pt is the shortest body the above-the-fold layout is budgeted
        // for. An SE or a mini cannot hold three wrapped rules plus the
        // masthead at this type size whatever the band does, and correctly
        // scrolls instead — there "at rest" is not a meaningful assertion.
        let height = app.windows.firstMatch.frame.height
        try XCTSkipUnless(height >= 844, "screen is \(height)pt; scrolling layout")

        for rule in rules {
            XCTAssertTrue(app.staticTexts[rule].isHittable,
                          "not on screen at rest: \(rule)")
        }
    }
}
