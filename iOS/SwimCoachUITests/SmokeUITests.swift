import XCTest

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
        app.launchArguments = ["-hasSeenOnboarding", "YES"] + args
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

    func testDemoCompareRendersPanels() {
        let app = launch(["-demoCompare"])
        XCTAssertTrue(app.staticTexts["EARLIER"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["LATER"].exists)
    }
}
