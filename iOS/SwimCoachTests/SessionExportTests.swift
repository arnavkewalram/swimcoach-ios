import XCTest
@testable import SwimCoach

final class SessionExportTests: XCTestCase {

    private func makeSession(score: Int, daysAgo: Int, name: String = "") -> SwimSession {
        let base = AnalysisResult.demo
        let result = AnalysisResult(
            id: UUID(), score: score, grade: "C",
            strokeCount: base.strokeCount, kickRatePerMin: base.kickRatePerMin,
            strokeAsymmetry: base.strokeAsymmetry, frameCount: base.frameCount,
            sampledFrames: base.sampledFrames, fps: base.fps,
            issues: base.issues, tips: base.tips,
            analyzedAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!)
        let session = SwimSession(result: result)
        session.name = name
        return session
    }

    func testArchiveRoundTripsAndSortsChronologically() throws {
        let sessions = [
            makeSession(score: 72, daysAgo: 0, name: "Latest"),
            makeSession(score: 60, daysAgo: 5, name: "Oldest"),
            makeSession(score: 66, daysAgo: 2),
        ]
        let data = try SessionExport.archiveData(from: sessions)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(SessionExport.Archive.self, from: data)

        XCTAssertEqual(archive.app, "SwimCoach")
        XCTAssertEqual(archive.sessions.count, 3)
        XCTAssertEqual(archive.sessions.first?.name, "Oldest")
        XCTAssertEqual(archive.sessions.last?.name, "Latest")
        XCTAssertEqual(archive.sessions.map(\.date), archive.sessions.map(\.date).sorted())
    }

    func testArchiveCarriesJournalFields() throws {
        let session = makeSession(score: 72, daysAgo: 0, name: "Threshold")
        session.notes = "felt strong"
        let data = try SessionExport.archiveData(from: [session])
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("\"name\" : \"Threshold\""))
        XCTAssertTrue(text.contains("\"notes\" : \"felt strong\""))
        XCTAssertTrue(text.contains("body_sag"), "fault names must be in the export")
        XCTAssertFalse(text.contains("keypointFrames"), "heavyweight payloads stay out")
    }

    func testDurationBackCompatAndStrokeRate() throws {
        // Old sessions (no durationSeconds) decode to nil and show no rate
        var data = try JSONEncoder().encode(AnalysisResult.demo)
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "durationSeconds")
        data = try JSONSerialization.data(withJSONObject: json)
        let legacy = try JSONDecoder().decode(AnalysisResult.self, from: data)
        XCTAssertNil(legacy.durationSeconds)
        XCTAssertNil(legacy.strokeRatePerMin)

        // Current fixture: 48 strokes over 60 s → 48 spm; round-trips
        XCTAssertEqual(try XCTUnwrap(AnalysisResult.demo.strokeRatePerMin), 48, accuracy: 0.001)
        let roundTrip = try JSONDecoder().decode(
            AnalysisResult.self, from: JSONEncoder().encode(AnalysisResult.demo))
        XCTAssertEqual(roundTrip.durationSeconds, 60)
    }

    func testEmptyStoreStillEncodes() throws {
        let data = try SessionExport.archiveData(from: [])
        XCTAssertFalse(data.isEmpty)
    }
}
