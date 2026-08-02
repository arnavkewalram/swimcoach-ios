import XCTest
@testable import SwimCoach

final class KeypointFrameTests: XCTestCase {

    private func frame(t: Double) -> KeypointFrame {
        KeypointFrame(t: t, joints: [Float](repeating: 0.5, count: 39))
    }

    // MARK: - nearest(to:)

    func testEmptyReturnsNil() {
        XCTAssertNil([KeypointFrame]().nearest(to: 1.0))
    }

    func testExactMatch() {
        let frames = [frame(t: 0.0), frame(t: 0.3), frame(t: 0.6)]
        XCTAssertEqual(frames.nearest(to: 0.3)?.t, 0.3)
    }

    func testPicksCloserNeighbor() {
        let frames = [frame(t: 0.0), frame(t: 0.3), frame(t: 0.6)]
        XCTAssertEqual(frames.nearest(to: 0.41)?.t, 0.3)
        XCTAssertEqual(frames.nearest(to: 0.49)?.t, 0.6)
    }

    func testBeyondToleranceReturnsNil() {
        let frames = [frame(t: 0.0), frame(t: 5.0)]
        XCTAssertNil(frames.nearest(to: 2.5))   // 2.5s from both — a dropout gap
    }

    func testBeforeFirstAndAfterLastWithinTolerance() {
        let frames = [frame(t: 1.0), frame(t: 1.3)]
        XCTAssertEqual(frames.nearest(to: 0.9)?.t, 1.0)
        XCTAssertEqual(frames.nearest(to: 1.5)?.t, 1.3)
    }

    // MARK: - point(_:)

    func testLowConfidenceJointReturnsNil() {
        var joints = [Float](repeating: 0.5, count: 39)
        joints[0 * 3 + 2] = 0.05   // below minConfidence
        let f = KeypointFrame(t: 0, joints: joints)
        XCTAssertNil(f.point(0))
        XCTAssertNotNil(f.point(1))
    }

    func testCodableRoundTrip() throws {
        let original = [frame(t: 0.1), frame(t: 0.4)]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([KeypointFrame].self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
