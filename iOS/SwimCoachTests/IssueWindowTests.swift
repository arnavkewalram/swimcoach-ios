import XCTest
@testable import SwimCoach

final class IssueWindowTests: XCTestCase {

    private func window(start: Double, sag: Float) -> IssueWindow {
        var probs = [Float](repeating: 0.13, count: 10)
        probs[6] = sag   // body_sag catalog index
        return IssueWindow(start: start, end: start + 3, probs: probs)
    }

    func testPeakWindowFindsMaximum() {
        let windows = [window(start: 0, sag: 0.4),
                       window(start: 1.5, sag: 0.9),
                       window(start: 3.0, sag: 0.6)]
        XCTAssertEqual(windows.peakWindow(labelIndex: 6)?.start, 1.5)
    }

    func testPeakWindowEmptyAndBadIndex() {
        XCTAssertNil([IssueWindow]().peakWindow(labelIndex: 6))
        XCTAssertNil([window(start: 0, sag: 0.5)].peakWindow(labelIndex: -1))
        XCTAssertNil([window(start: 0, sag: 0.5)].peakWindow(labelIndex: 99))
    }

    func testLabelIndexMatchesCatalogOrder() {
        XCTAssertEqual(FeedbackEngine.labelIndex(of: "left_elbow_overextension"), 0)
        XCTAssertEqual(FeedbackEngine.labelIndex(of: "body_sag"), 6)
        XCTAssertEqual(FeedbackEngine.labelIndex(of: "excessive_kick_rate"), 9)
        XCTAssertNil(FeedbackEngine.labelIndex(of: "not_a_label"))
    }

    func testCodableRoundTrip() throws {
        let original = [window(start: 0, sag: 0.5), window(start: 1.5, sag: 0.7)]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([IssueWindow].self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
