import XCTest
import AVFoundation
@testable import SwimCoach

final class OverlayVideoExporterTests: XCTestCase {

    func testPixelPointsFlipYAndScale() {
        // Joint 0 at Vision (0.25, 0.75) — near top-left in screen terms
        var joints = [Float](repeating: 0, count: 39)
        joints[0] = 0.25; joints[1] = 0.75; joints[2] = 0.9
        let frame = KeypointFrame(t: 0, joints: joints)
        let points = OverlayVideoExporter.pixelPoints(for: frame, size: CGSize(width: 1000, height: 500))
        XCTAssertEqual(points.count, 13)
        XCTAssertEqual(points[0]?.x ?? -1, 250, accuracy: 0.001)
        XCTAssertEqual(points[0]?.y ?? -1, 125, accuracy: 0.001)   // (1 - 0.75) * 500
    }

    func testLowConfidenceJointsAreNil() {
        var joints = [Float](repeating: 0, count: 39)
        joints[0] = 0.5; joints[1] = 0.5; joints[2] = 0.05   // below minConfidence
        joints[3] = 0.5; joints[4] = 0.5; joints[5] = 0.9
        let frame = KeypointFrame(t: 0, joints: joints)
        let points = OverlayVideoExporter.pixelPoints(for: frame, size: CGSize(width: 100, height: 100))
        XCTAssertNil(points[0])
        XCTAssertNotNil(points[1])
    }

    func testFullExportProducesPlayableVideo() async throws {
        guard let url = Bundle.main.url(forResource: "swim_test", withExtension: "mp4") else {
            throw XCTSkip("demo video not bundled")
        }
        let out = try await OverlayVideoExporter.export(
            videoURL: url, frames: AnalysisResult.demoKeypointFrames, progress: { _ in })
        defer { try? FileManager.default.removeItem(at: out) }

        let attrs = try FileManager.default.attributesOfItem(atPath: out.path)
        XCTAssertGreaterThan((attrs[.size] as? Int) ?? 0, 10_000, "export suspiciously small")

        let asset = AVURLAsset(url: out)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let duration = try await asset.load(.duration).seconds
        XCTAssertGreaterThan(duration, 5.0)
    }

    func testDemoFixtureFramesAreWellFormed() {
        let frames = AnalysisResult.demoKeypointFrames
        XCTAssertEqual(frames.count, 27)
        XCTAssertTrue(frames.allSatisfy { $0.joints.count == 39 })
        // Time-ordered for nearest() binary search
        XCTAssertEqual(frames.map(\.t), frames.map(\.t).sorted())
    }
}
