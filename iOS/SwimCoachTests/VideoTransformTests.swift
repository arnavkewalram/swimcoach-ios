import XCTest
import CoreGraphics
@testable import SwimCoach

final class VideoTransformTests: XCTestCase {

    // iPhone portrait recording: landscape sensor frames + 90° CW transform
    private let portrait = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
    private let landscapeFlipped = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1920, ty: 1080)
    private let raw = CGSize(width: 1920, height: 1080)

    func testOrientationMapping() {
        XCTAssertEqual(VideoTransform.orientation(for: .identity), .up)
        XCTAssertEqual(VideoTransform.orientation(for: portrait), .right)
        XCTAssertEqual(VideoTransform.orientation(
            for: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1920)), .left)
        XCTAssertEqual(VideoTransform.orientation(for: landscapeFlipped), .down)
    }

    func testDisplaySizeSwapsForPortrait() {
        XCTAssertEqual(VideoTransform.displaySize(natural: raw, transform: .identity), raw)
        XCTAssertEqual(VideoTransform.displaySize(natural: raw, transform: portrait),
                       CGSize(width: 1080, height: 1920))
        XCTAssertEqual(VideoTransform.displaySize(natural: raw, transform: landscapeFlipped), raw)
    }

    func testIdentityRawPointMatchesDirectMapping() {
        // With no rotation the mapping is the classic x*W / (1-y)*H
        let p = VideoTransform.rawPixelPoint(
            visionDisplayPoint: CGPoint(x: 0.25, y: 0.75), natural: raw, transform: .identity)
        XCTAssertEqual(p.x, 480, accuracy: 0.001)
        XCTAssertEqual(p.y, 270, accuracy: 0.001)   // (1 - 0.75) * 1080
    }

    func testPortraitRawPointMapsThroughRotation() {
        // Display space is 1080×1920 under t:(x,y)→(1080−y, x). The
        // display top edge is the sensor frame's LEFT edge: top-center
        // (x 0.5, Vision y 1.0) → raw left-center (0, 540).
        let top = VideoTransform.rawPixelPoint(
            visionDisplayPoint: CGPoint(x: 0.5, y: 1.0), natural: raw, transform: portrait)
        XCTAssertEqual(top.x, 0, accuracy: 0.001)
        XCTAssertEqual(top.y, 540, accuracy: 0.001)

        // Display bottom-left corner (x 0, Vision y 0) → raw bottom-right
        let corner = VideoTransform.rawPixelPoint(
            visionDisplayPoint: CGPoint(x: 0, y: 0), natural: raw, transform: portrait)
        XCTAssertEqual(corner.x, 1920, accuracy: 0.001)
        XCTAssertEqual(corner.y, 1080, accuracy: 0.001)
    }

    func testFlippedLandscapeRawPointMirrorsBothAxes() {
        let p = VideoTransform.rawPixelPoint(
            visionDisplayPoint: CGPoint(x: 0.25, y: 0.75), natural: raw, transform: landscapeFlipped)
        XCTAssertEqual(p.x, 1920 - 480, accuracy: 0.001)
        XCTAssertEqual(p.y, 1080 - 270, accuracy: 0.001)
    }
}
