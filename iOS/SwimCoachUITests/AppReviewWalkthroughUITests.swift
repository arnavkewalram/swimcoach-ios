import XCTest

/// Drives the app through its typical flow at a watchable pace, for the
/// screen recording App Review asks new developer accounts to supply
/// (Guideline 2.1 "Information Needed"): the recording must begin with
/// launching the app on a physical device.
///
/// Not an assertion suite — it fails only if the flow itself breaks. Run it
/// on a device while `devicectl device capture screen-record` is recording.
/// Record against a Release build of the app: the Debug build's Home carries
/// a DEV TOOLS panel that must not appear in footage sent to Apple.
/// `docs/APP_STORE_SUBMISSION.md` has the exact procedure.
///
/// Skips in the simulator: Vision cannot analyze there, so the flow would
/// stop at the sample swim.
final class AppReviewWalkthroughUITests: XCTestCase {

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("The walkthrough analyzes a real clip, which needs a physical device.")
        #endif
        continueAfterFailure = false
    }

    func testTypicalUserFlow() {
        // 1 — Launch from the Home Screen, as a user would.
        XCUIDevice.shared.press(.home)
        pause(2)
        let app = XCUIApplication()
        // Not a DEBUG hook: keeps the What's New sheet from covering Home.
        app.launchArguments = ["-suppressWhatsNew"]
        app.launch()
        pause(3)
        attach("01-launch")
        passOnboardingIfShown(app)

        // 2 — Home.
        XCTAssertTrue(app.buttons["Analyze a swim"].waitForExistence(timeout: 15),
                      "Home never appeared")
        pause(3)
        attach("02-home")

        // 3 — Recording screen: framing guide and level indicator.
        app.buttons["Analyze a swim"].tap()
        pause(2)
        answerPermissionPrompts()
        pause(5)
        attach("03-camera")
        let closeCamera = app.buttons["Close camera"]
        if closeCamera.waitForExistence(timeout: 5) { closeCamera.tap() }
        pause(2)

        // 4 — Try a sample swim (App Review has no pool).
        openSampleSwims(app)
        XCTAssertTrue(app.descendants(matching: .any)["sampleSwimsScreen"]
            .waitForExistence(timeout: 10), "the sample swims screen never opened")
        pause(3)
        attach("04-samples")
        let clip = app.descendants(matching: .any)["sampleClipRow-sample_crawl_deck"]
        scroll(app, to: clip)
        pause(2)
        clip.tap()

        // 5 — Real on-device analysis, then Results.
        let score = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Technique score")).firstMatch
        XCTAssertTrue(score.waitForExistence(timeout: 120), "the sample never reached Results")
        pause(4)
        attach("05-results")

        // 6 — A detected fault, and the drills that address it. Found before
        // the tour of the rest of Results, which scrolls past the Issues list.
        let fault = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "severity")).firstMatch
        XCTAssertTrue(scroll(app, to: fault), "no detected fault on Results to open")
        pause(2)
        fault.tap()
        pause(3)
        attach("06-fault-expanded")
        let drills = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Open drills that fix")).firstMatch
        XCTAssertTrue(scroll(app, to: drills), "the expanded fault offers no drills")
        drills.tap()
        pause(4)
        attach("06-drills")
        app.swipeUp(velocity: .slow)
        pause(3)
        goBack(app)

        // The rest of Results: timeline, stroke stats, the full readout.
        for _ in 0..<4 {
            app.swipeUp(velocity: .slow)
            pause(2)
        }
        attach("06-results-readout")
        goBack(app)
        pause(3)

        // 7 — About: what the app does with your data (nothing leaves the phone).
        let about = app.buttons["About SwimCoach"]
        if scroll(app, to: about) {
            about.tap()
            pause(3)
            attach("07-about")
            for _ in 0..<3 {
                app.swipeUp(velocity: .slow)
                pause(2)
            }
            goBack(app)
        }
        pause(3)
    }

    // MARK: - Steps

    private func passOnboardingIfShown(_ app: XCUIApplication) {
        guard app.buttons["Skip the intro"].waitForExistence(timeout: 3) else { return }
        // Page through rather than skipping, so the recording shows the intro.
        for _ in 0..<4 where app.buttons["Skip the intro"].exists {
            pause(3)
            // The CTA retitles per page: Get started → Next → Start analyzing.
            app.buttons.matching(NSPredicate(format: "label IN %@",
                                             ["Get started", "Next", "Start analyzing"]))
                .firstMatch.tap()
        }
        pause(2)
    }

    private func openSampleSwims(_ app: XCUIApplication) {
        let card = app.buttons["Try a sample swim"]
        if card.exists && card.isHittable {
            card.tap()
            return
        }
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sample swims")).firstMatch
        scroll(app, to: row)
        row.tap()
    }

    /// Camera, then microphone — the recording screen asks for both.
    private func answerPermissionPrompts() {
        for _ in 0..<2 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 3) else { return }
            pause(1)
            for title in ["Allow", "OK", "Allow While Using App"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                break
            }
        }
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        if back.exists && back.isHittable {
            back.tap()
        } else {
            app.swipeDown(velocity: .fast)
        }
        pause(2)
    }

    // MARK: - Helpers

    @discardableResult
    private func scroll(_ app: XCUIApplication, to target: XCUIElement) -> Bool {
        for _ in 0..<10 {
            if target.exists && target.isHittable { return true }
            app.swipeUp(velocity: .slow)
        }
        return target.exists && target.isHittable
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// A still per step in the result bundle, to check the take without
    /// scrubbing the video.
    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
