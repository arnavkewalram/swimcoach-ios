import XCTest
@testable import SwimCoach

/// The Results footer's claim about persistence, and the sample check that
/// feeds it.
///
/// A sample swim is never saved (`AnalyzingView` skips it on purpose), so a
/// footer that only knew "saved" and "not saved" reported a storage error on
/// every sample — the flow the App Review notes send reviewers down.
final class ResultsSaveStatusTests: XCTestCase {

    // MARK: - The three states

    func testASavedResultSaysSo() {
        let status = ResultsSaveStatus(isSaved: true, isSample: false)
        XCTAssertEqual(status, .saved)
        XCTAssertFalse(status.isError)
        XCTAssertEqual(status.message, "Session saved")
    }

    func testAnUnsavedSampleIsNotAnError() {
        let status = ResultsSaveStatus(isSaved: false, isSample: true)
        XCTAssertEqual(status, .sample)
        XCTAssertFalse(status.isError)
        XCTAssertFalse(status.message.localizedCaseInsensitiveContains("error"),
                       "a deliberate skip must not read as a failure: \(status.message)")
        XCTAssertTrue(status.message.contains("not saved to your history"),
                      "the footer should say why the sample was not saved")
    }

    func testAnUnsavedOwnSwimIsStillReportedAsAFailure() {
        let status = ResultsSaveStatus(isSaved: false, isSample: false)
        XCTAssertEqual(status, .failed)
        XCTAssertTrue(status.isError)
        XCTAssertTrue(status.message.contains("storage error"))
    }

    func testSavedWinsIfTheStoreHasIt() {
        // Not reachable today — samples never reach the store — but if one
        // ever did, the footer must describe what is actually on disk.
        XCTAssertEqual(ResultsSaveStatus(isSaved: true, isSample: true), .saved)
    }

    func testEveryStateHasItsOwnSymbol() {
        let symbols = [ResultsSaveStatus.saved, .sample, .failed].map(\.symbolName)
        XCTAssertEqual(Set(symbols).count, symbols.count)
    }

    // MARK: - The sample check Results relies on

    /// Results decides "sample" from `result.videoURL`, which resolves the
    /// stored file name back to a URL. For a sample that name is the bundled
    /// clip's (`SessionVideoStore.persist` references bundle resources by
    /// name), so the round trip has to land on the exact URL the catalog
    /// recognises — for every clip.
    func testEverySampleResultResolvesBackToASample() throws {
        for clip in SampleClipCatalog.all {
            let result = makeResult(videoFileName: clip.fileName)
            let url = try XCTUnwrap(result.videoURL, "\(clip.fileName) did not resolve")
            XCTAssertTrue(SampleClipCatalog.isSample(url),
                          "\(clip.fileName) resolved to \(url), which is not recognised as a sample")
        }
    }

    func testAUserSwimIsNotASample() {
        let result = makeResult(videoFileName: "\(UUID().uuidString).mov")
        XCTAssertFalse(result.videoURL.map { SampleClipCatalog.isSample($0) } ?? false)
    }

    // MARK: - Helpers

    private func makeResult(videoFileName: String) -> AnalysisResult {
        var result = AnalysisResult(
            id: UUID(), score: 80, grade: "B",
            strokeCount: 4, kickRatePerMin: 0, strokeAsymmetry: 0.5,
            frameCount: 20, sampledFrames: 20, fps: 30,
            issues: [], tips: [], analyzedAt: Date())
        result.videoFileName = videoFileName
        return result
    }
}
