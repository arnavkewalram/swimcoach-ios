import XCTest
@testable import SwimCoach

final class ReportCardTests: XCTestCase {

    @MainActor
    func testRenderProducesShareableImageAtTargetSize() {
        let image = ReportCardView.render(
            result: .demo,
            trendScores: [58, 61, 64, 67, 70, 72],
            newBest: true)
        XCTAssertNotNil(image)
        // 540×675 @2x → 1080×1350 (Instagram portrait)
        XCTAssertEqual((image?.size.width ?? 0) * (image?.scale ?? 0), 1080)
        XCTAssertEqual((image?.size.height ?? 0) * (image?.scale ?? 0), 1350)
    }

    @MainActor
    func testRenderWithoutTrendStillWorks() {
        XCTAssertNotNil(ReportCardView.render(result: .demo))
    }
}
