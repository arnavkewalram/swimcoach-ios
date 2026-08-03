import XCTest
@testable import SwimCoach

final class WeeklyGoalStoreTests: XCTestCase {

    private static let suiteName = "WeeklyGoalStoreTests"
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

    // MARK: - Everyone scope (legacy key migration)

    func testExistingGlobalGoalBecomesEveryoneGoal() {
        // Arrange — a goal saved before per-swimmer scoping existed
        defaults.set(3, forKey: WeeklyGoalStore.everyoneKey)
        let store = WeeklyGoalStore(defaults: defaults)

        // Act
        let goal = store.goal(for: "")

        // Assert
        XCTAssertEqual(goal, 3)
    }

    func testEveryoneWritesUseTheLegacyGlobalKey() {
        // Arrange
        let store = WeeklyGoalStore(defaults: defaults)

        // Act
        store.setGoal(4, for: "")

        // Assert
        XCTAssertEqual(defaults.integer(forKey: WeeklyGoalStore.everyoneKey), 4)
        XCTAssertEqual(store.goal(for: ""), 4)
    }

    // MARK: - Per-swimmer scope

    func testSwimmerWithoutExplicitGoalInheritsEveryoneGoal() {
        // Arrange
        let store = WeeklyGoalStore(defaults: defaults)
        store.setGoal(3, for: "")

        // Act
        let goal = store.goal(for: "Maya")

        // Assert
        XCTAssertEqual(goal, 3)
    }

    func testExplicitSwimmerGoalOverridesEveryoneGoal() {
        // Arrange
        let store = WeeklyGoalStore(defaults: defaults)
        store.setGoal(3, for: "")

        // Act
        store.setGoal(5, for: "Maya")

        // Assert
        XCTAssertEqual(store.goal(for: "Maya"), 5)
        XCTAssertEqual(store.goal(for: ""), 3)        // Everyone untouched
        XCTAssertEqual(store.goal(for: "Leo"), 3)     // others still inherit
    }

    func testExplicitZeroTurnsGoalOffDespiteEveryoneGoal() {
        // Arrange
        let store = WeeklyGoalStore(defaults: defaults)
        store.setGoal(3, for: "")

        // Act — Maya opts out of the shared goal
        store.setGoal(0, for: "Maya")

        // Assert
        XCTAssertEqual(store.goal(for: "Maya"), 0)
        XCTAssertEqual(store.goal(for: ""), 3)
    }

    func testSwimmerWriteDoesNotTouchTheGlobalKey() {
        // Arrange
        let store = WeeklyGoalStore(defaults: defaults)

        // Act
        store.setGoal(5, for: "Maya")

        // Assert
        XCTAssertNil(defaults.object(forKey: WeeklyGoalStore.everyoneKey))
        XCTAssertEqual(store.goal(for: ""), 0)
    }

    func testGoalsForMultipleSwimmersLiveInOneDictionary() {
        // Arrange
        let store = WeeklyGoalStore(defaults: defaults)

        // Act
        store.setGoal(5, for: "Maya")
        store.setGoal(2, for: "Leo")

        // Assert
        let stored = defaults.dictionary(forKey: WeeklyGoalStore.swimmersKey) as? [String: Int]
        XCTAssertEqual(stored, ["Maya": 5, "Leo": 2])
        XCTAssertEqual(store.goal(for: "Maya"), 5)
        XCTAssertEqual(store.goal(for: "Leo"), 2)
    }

    func testCorruptDictionaryEntriesAreDroppedNotTrusted() {
        // Arrange — one bad entry, one good one
        defaults.set(["Maya": "five", "Leo": 4], forKey: WeeklyGoalStore.swimmersKey)
        defaults.set(3, forKey: WeeklyGoalStore.everyoneKey)
        let store = WeeklyGoalStore(defaults: defaults)

        // Act & Assert — bad entry falls back, good entry survives
        XCTAssertEqual(store.goal(for: "Maya"), 3)
        XCTAssertEqual(store.goal(for: "Leo"), 4)
    }

    // MARK: - Pure core

    func testResolvePrefersExplicitGoalOverFallback() {
        // Arrange
        let goals = ["Maya": 5]

        // Act
        let maya = WeeklyGoalStore.resolve(swimmer: "Maya", everyoneGoal: 3, swimmerGoals: goals)
        let leo = WeeklyGoalStore.resolve(swimmer: "Leo", everyoneGoal: 3, swimmerGoals: goals)
        let everyone = WeeklyGoalStore.resolve(swimmer: "", everyoneGoal: 3, swimmerGoals: goals)

        // Assert
        XCTAssertEqual(maya, 5)
        XCTAssertEqual(leo, 3)
        XCTAssertEqual(everyone, 3)
    }

    func testUpdatingReturnsNewDictionaryAndLeavesInputUntouched() {
        // Arrange
        let original = ["Maya": 5]

        // Act
        let updated = WeeklyGoalStore.updating(original, swimmer: "Leo", goal: 2)

        // Assert
        XCTAssertEqual(updated, ["Maya": 5, "Leo": 2])
        XCTAssertEqual(original, ["Maya": 5])
    }

    func testUpdatingOverwritesAnExistingEntry() {
        // Arrange
        let original = ["Maya": 5]

        // Act
        let updated = WeeklyGoalStore.updating(original, swimmer: "Maya", goal: 1)

        // Assert
        XCTAssertEqual(updated, ["Maya": 1])
    }

    func testUpdatingPassesEveryoneScopeThroughUnchanged() {
        // Arrange
        let original = ["Maya": 5]

        // Act — "" is not a dictionary entry; it lives on the global key
        let updated = WeeklyGoalStore.updating(original, swimmer: "", goal: 9)

        // Assert
        XCTAssertEqual(updated, original)
    }
}
