import XCTest

/// End-to-end proof for "keep the swim, drop the footage".
///
/// The unit tests pin the policy; this pins the thing that would actually hurt
/// — that after a real delete on a real store, the swims are still there, the
/// footage is not, and none of it comes back as a recoverable take on the next
/// launch (the v1.45.3 symptom, from the other direction).
///
/// State is carried across launches deliberately: the seeds run once, and every
/// later launch reads what the previous one left on disk.
final class ClipStorageUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenOnboarding", "YES", "-suppressWhatsNew"] + args
        app.launch()
        return app
    }

    /// About is a scroll view and clip storage sits below the fold.
    @discardableResult
    private func scroll(_ app: XCUIApplication, to target: XCUIElement,
                        maxSwipes: Int = 8) -> Bool {
        for _ in 0..<maxSwipes {
            if target.exists && target.isHittable { return true }
            app.swipeUp()
        }
        return target.exists && target.isHittable
    }

    /// Keep what the run actually saw. A failure here is "the wrong number of
    /// clips went", which is very hard to read from an assertion message and
    /// obvious from the frame — and the section lives below the fold, so it is
    /// otherwise unphotographable from outside the test.
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The seeded fixture: four session clips back-dated 1 / 45 / 120 / 500
    /// days, plus the two unfinished takes `-seedUnfinishedTakes` writes.
    func testDroppingFootageKeepsTheSwimsAndResurrectsNothing() {
        // ── 1. Seed, and read what the store costs ──────────────────────
        let seeded = launch(["-seedTrainingLog", "-seedUnfinishedTakes",
                             "-seedStoredClips", "-openAbout"])
        XCTAssertTrue(seeded.staticTexts["PRIVACY"].waitForExistence(timeout: 20))

        let total = element(seeded, "clipStorageTotal")
        XCTAssertTrue(scroll(seeded, to: total), "The clip-storage section never appeared")
        XCTAssertTrue(total.label.contains("6 clips"),
                      "four session clips plus two takes — read: \(total.label)")
        XCTAssertTrue(total.label.contains("MB") || total.label.contains("KB"),
                      "the headline must be a size, not a count — read: \(total.label)")
        XCTAssertTrue(seeded.staticTexts["4 clips belong to saved swims; 2 are still waiting to be scored."].exists,
                      "the breakdown has to reconcile with the total")
        capture(seeded, "01-priced")

        // Each age prices its own set: 500d / 120d+500d / 45d+120d+500d / all.
        XCTAssertTrue(element(seeded, "clipStorageCutoff-365").label.contains("1 clip,"))
        XCTAssertTrue(element(seeded, "clipStorageCutoff-90").label.contains("2 clips,"))
        XCTAssertTrue(element(seeded, "clipStorageCutoff-30").label.contains("3 clips,"))
        XCTAssertTrue(element(seeded, "clipStorageCutoff-0").label.contains("4 clips,"))
        seeded.terminate()

        // ── 2. The footage is really there before we take it away ───────
        let before = launch(["-openHistory"])
        XCTAssertTrue(before.staticTexts["Threshold Tuesday"].waitForExistence(timeout: 20),
                      "the seeded sessions must survive a relaunch for any of this to mean anything")
        before.staticTexts["Threshold Tuesday"].tap()
        XCTAssertTrue(before.staticTexts["TECHNIQUE SCORE"].waitForExistence(timeout: 15))
        XCTAssertTrue(before.staticTexts["VIDEO · 1:00"].exists,
                      "precondition: Results plays this session's clip")
        before.terminate()

        // ── 3. Drop it ──────────────────────────────────────────────────
        let app = launch(["-openAbout"])
        XCTAssertTrue(app.staticTexts["PRIVACY"].waitForExistence(timeout: 20))
        let anyAge = element(app, "clipStorageCutoff-0")
        XCTAssertTrue(scroll(app, to: anyAge))
        anyAge.tap()

        let delete = element(app, "clipStorageDelete")
        XCTAssertTrue(scroll(app, to: delete), "no delete control for a non-empty selection")
        XCTAssertTrue(delete.label.contains("Delete 4 clips"), "read: \(delete.label)")
        capture(app, "02-any-age-selected")
        delete.tap()

        let confirm = app.buttons["Delete 4 clips"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5),
                      "a destructive control must ask before it acts")
        capture(app, "03-confirmation")
        confirm.tap()

        // The two takes are still there, so the section stays — but there is
        // nothing left it may delete, and it stops offering to.
        XCTAssertTrue(delete.waitForNonExistence(timeout: 5),
                      "the control must not survive with an empty delete set")
        XCTAssertTrue(element(app, "clipStorageEmptyNote").exists)
        XCTAssertTrue(element(app, "clipStorageTotal").label.contains("2 clips"),
                      "read: \(element(app, "clipStorageTotal").label)")
        capture(app, "04-after-delete")
        app.terminate()

        // ── 4. Nothing came back as a recoverable take ──────────────────
        let takes = launch(["-openTakes"])
        let header = element(takes, "unfinishedTakesHeader")
        XCTAssertTrue(header.waitForExistence(timeout: 20))
        XCTAssertTrue(header.label.contains("2 WAITING"),
                      "the four deleted session clips must not be offered back — read: \(header.label)")
        takes.terminate()

        // ── 5. The swims, their scores and their notes are untouched ────
        let after = launch(["-openHistory"])
        XCTAssertTrue(after.staticTexts["Threshold Tuesday"].waitForExistence(timeout: 20),
                      "deleting footage must not delete a session")
        after.staticTexts["Threshold Tuesday"].tap()
        XCTAssertTrue(after.staticTexts["TECHNIQUE SCORE"].waitForExistence(timeout: 15))
        XCTAssertTrue(after.staticTexts["72"].exists, "the score is what was kept")
        XCTAssertTrue(after.staticTexts["ISSUES DETECTED"].exists, "the faults are kept too")
        XCTAssertFalse(after.staticTexts["VIDEO · 1:00"].exists,
                       "Results must simply drop its video section, not break on the missing file")
        XCTAssertFalse(after.staticTexts["SESSION VIDEO"].exists)
        capture(after, "05-results-without-video")
    }

    /// A store with nothing a session claims must show what it costs and offer
    /// no delete at all — every age it could name would remove zero clips.
    func testStoreOfOnlyTakesReportsItselfButOffersNoDelete() {
        let app = launch(["-seedTrainingLog", "-seedUnfinishedTakes", "-openAbout"])
        XCTAssertTrue(app.staticTexts["PRIVACY"].waitForExistence(timeout: 20))

        let total = element(app, "clipStorageTotal")
        XCTAssertTrue(scroll(app, to: total))
        XCTAssertTrue(total.label.contains("of video stored"), "read: \(total.label)")
        XCTAssertTrue(element(app, "clipStorageEmptyNote").exists)
        XCTAssertFalse(element(app, "clipStorageDelete").exists,
                       "a control that would delete nothing must not be offered")
        XCTAssertFalse(app.staticTexts["DELETE CLIPS OLDER THAN"].exists)
    }
}
