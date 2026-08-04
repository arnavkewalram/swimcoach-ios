import XCTest
@testable import SwimCoach

/// The export state box `ResultsView` no longer owns. Splitting it out was a
/// render-scope change, and body invalidation is not assertable from XCTest —
/// what these pin is that the behaviour survived the move: the control opens at
/// 0%, and every way out of an export lands on a terminal state rather than
/// sticking at n%.
@MainActor
final class OverlayExportModelTests: XCTestCase {

    private func demoClip() throws -> URL {
        guard let url = Bundle.main.url(forResource: "swim_test", withExtension: "mp4") else {
            throw XCTSkip("demo video not bundled")
        }
        return url
    }

    func testStartsIdleSoTheControlOffersExport() {
        XCTAssertEqual(OverlayExportModel().state, .idle)
    }

    func testStartShowsZeroPercentImmediately() throws {
        let model = OverlayExportModel()
        model.start(videoURL: try demoClip(), frames: AnalysisResult.demoKeypointFrames)
        defer { model.cancel() }
        XCTAssertEqual(model.state, .exporting(0),
                       "the control must read 0% the instant it is tapped, before any pump report")
    }

    func testCancelReturnsToIdleSoTheControlOffersExportAgain() async throws {
        let model = OverlayExportModel()
        model.start(videoURL: try demoClip(), frames: AnalysisResult.demoKeypointFrames)
        model.cancel()

        // The exporter unwinds through its own cancellation handler; poll for
        // the terminal state rather than sleeping a tuned interval.
        let deadline = Date().addingTimeInterval(30)
        while model.state != .idle && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(model.state, .idle,
                       "a cancelled export must return to EXPORT, not strand the control at n%")
    }

    func testExportReachesReadyWithTheFileItProduced() async throws {
        let model = OverlayExportModel()
        model.start(videoURL: try demoClip(), frames: AnalysisResult.demoKeypointFrames)

        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if case .ready = model.state { break }
            if case .failed = model.state { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        guard case .ready(let url) = model.state else {
            return XCTFail("export did not reach .ready — state was \(model.state)")
        }
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
