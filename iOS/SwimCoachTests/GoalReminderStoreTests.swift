import XCTest
@testable import SwimCoach

final class GoalReminderStoreTests: XCTestCase {

    private static let suiteName = "GoalReminderStoreTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: Self.suiteName)
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: Self.suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Defaults

    func testFreshStoreDefaultsToDisabledFridayFivePM() {
        // Arrange
        let store = GoalReminderStore(defaults: defaults)

        // Act
        let settings = store.settings(for: "")

        // Assert
        XCTAssertEqual(settings,
            GoalReminderStore.Settings(isEnabled: false, weekday: 6,
                                       hour: 17, minute: 0))
    }

    // MARK: - Round trips and scoping

    func testEveryoneSettingsRoundTripOnTheEveryoneKey() {
        // Arrange
        let store = GoalReminderStore(defaults: defaults)
        let chosen = GoalReminderStore.Settings(isEnabled: true, weekday: 3,
                                                hour: 7, minute: 30)

        // Act
        store.setSettings(chosen, for: "")

        // Assert
        XCTAssertEqual(store.settings(for: ""), chosen)
        XCTAssertNotNil(defaults.dictionary(forKey: GoalReminderStore.everyoneKey))
        XCTAssertNil(defaults.dictionary(forKey: GoalReminderStore.swimmersKey))
    }

    func testSwimmerWithoutExplicitSettingsInheritsEveryone() {
        // Arrange
        let store = GoalReminderStore(defaults: defaults)
        let shared = GoalReminderStore.Settings(isEnabled: true, weekday: 2,
                                                hour: 18, minute: 0)
        store.setSettings(shared, for: "")

        // Act
        let settings = store.settings(for: "Maya")

        // Assert
        XCTAssertEqual(settings, shared)
    }

    func testExplicitSwimmerSettingsBeatEveryoneIncludingDisabled() {
        // Arrange — Everyone reminds; Maya explicitly opts out
        let store = GoalReminderStore(defaults: defaults)
        store.setSettings(.init(isEnabled: true, weekday: 6, hour: 17,
                                minute: 0), for: "")
        let optOut = GoalReminderStore.Settings(isEnabled: false, weekday: 6,
                                                hour: 17, minute: 0)

        // Act
        store.setSettings(optOut, for: "Maya")

        // Assert
        XCTAssertEqual(store.settings(for: "Maya"), optOut)
        XCTAssertTrue(store.settings(for: "").isEnabled)   // Everyone untouched
        XCTAssertTrue(store.settings(for: "Leo").isEnabled) // others inherit
    }

    func testCorruptStoredEntriesFallBackInsteadOfBeingTrusted() {
        // Arrange — weekday out of range and a non-dictionary entry
        defaults.set(["Maya": ["enabled": 1, "weekday": 9, "hour": 17, "minute": 0],
                      "Leo": "junk"],
                     forKey: GoalReminderStore.swimmersKey)
        let store = GoalReminderStore(defaults: defaults)

        // Act & Assert — both drop to defaults rather than half-decoding
        XCTAssertEqual(store.settings(for: "Maya"), .initial)
        XCTAssertEqual(store.settings(for: "Leo"), .initial)
    }

    // MARK: - Pure core

    func testUpdatingReturnsNewDictionaryAndLeavesInputUntouched() {
        // Arrange
        let original = ["Maya": GoalReminderStore.Settings(isEnabled: true,
                                                           weekday: 2,
                                                           hour: 6, minute: 0)]
        let leo = GoalReminderStore.Settings(isEnabled: true, weekday: 4,
                                             hour: 19, minute: 15)

        // Act
        let updated = GoalReminderStore.updating(original, swimmer: "Leo",
                                                 settings: leo)

        // Assert
        XCTAssertEqual(updated["Leo"], leo)
        XCTAssertEqual(updated.count, 2)
        XCTAssertEqual(original.count, 1)
    }

    func testUpdatingPassesEveryoneScopeThroughUnchanged() {
        // Arrange
        let original = ["Maya": GoalReminderStore.Settings.initial]

        // Act — "" is not a dictionary entry; it lives on the Everyone key
        let updated = GoalReminderStore.updating(
            original, swimmer: "", settings: .init(isEnabled: true, weekday: 1,
                                                   hour: 9, minute: 0))

        // Assert
        XCTAssertEqual(updated, original)
    }

    func testEncodeDecodeRoundTripsEveryField() {
        // Arrange
        let settings = GoalReminderStore.Settings(isEnabled: true, weekday: 7,
                                                  hour: 23, minute: 59)

        // Act
        let decoded = GoalReminderStore.decode(GoalReminderStore.encode(settings))

        // Assert
        XCTAssertEqual(decoded, settings)
    }

    func testDecodeRejectsOutOfRangeFields() {
        // Arrange
        let base = GoalReminderStore.encode(.initial)
        var badHour = base; badHour["hour"] = 24
        var badMinute = base; badMinute["minute"] = -1
        var badWeekday = base; badWeekday["weekday"] = 0

        // Act & Assert
        XCTAssertNil(GoalReminderStore.decode(badHour))
        XCTAssertNil(GoalReminderStore.decode(badMinute))
        XCTAssertNil(GoalReminderStore.decode(badWeekday))
        XCTAssertNil(GoalReminderStore.decode(nil))
    }
}
