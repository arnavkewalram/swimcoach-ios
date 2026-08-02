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

    func testEmptyStoreStillEncodes() throws {
        let data = try SessionExport.archiveData(from: [])
        XCTAssertFalse(data.isEmpty)
    }
}
