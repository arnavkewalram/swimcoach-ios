import XCTest
@testable import SwimCoach

final class LevelMathTests: XCTestCase {

    func testPortraitUprightIsZero() {
        // Portrait: gravity points straight down the long axis
        XCTAssertEqual(LevelMath.rollDegrees(gravityX: 0, gravityY: -1), 0, accuracy: 0.001)
    }

    func testQuarterTurnIsNinetyDegrees() {
        XCTAssertEqual(LevelMath.rollDegrees(gravityX: 1, gravityY: 0), 90, accuracy: 0.001)
        XCTAssertEqual(LevelMath.rollDegrees(gravityX: -1, gravityY: 0), -90, accuracy: 0.001)
    }

    func testSmallTiltSign() {
        let right = LevelMath.rollDegrees(gravityX: 0.05, gravityY: -0.9987)
        XCTAssertGreaterThan(right, 0)
        XCTAssertEqual(right, 2.866, accuracy: 0.01)
        let left = LevelMath.rollDegrees(gravityX: -0.05, gravityY: -0.9987)
        XCTAssertEqual(left, -right, accuracy: 0.001)
    }

    func testIsLevelTolerance() {
        XCTAssertTrue(LevelMath.isLevel(0))
        XCTAssertTrue(LevelMath.isLevel(2.0))
        XCTAssertTrue(LevelMath.isLevel(-2.0))
        XCTAssertFalse(LevelMath.isLevel(2.1))
        XCTAssertFalse(LevelMath.isLevel(-5))
        XCTAssertTrue(LevelMath.isLevel(4, tolerance: 5))
    }
}
