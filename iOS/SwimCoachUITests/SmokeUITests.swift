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
