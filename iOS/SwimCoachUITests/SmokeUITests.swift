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
}
