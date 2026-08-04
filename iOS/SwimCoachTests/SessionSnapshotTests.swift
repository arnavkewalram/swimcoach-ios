import XCTest
@testable import SwimCoach

/// The snapshot layer exists so exports can be built off the main thread
/// without reading SwiftData models off their context's actor. Its whole
/// contract is that it changes *nothing* about the bytes — these tests pin
/// the model-backed and snapshot-backed paths to each other.
final class SessionSnapshotTests: XCTestCase {

    private func makeSession(name: String = "",
                             swimmer: String = "",
                             notes: String = "",
                             analyzedAt: Date = Date(),
                             durationSeconds: Double? = nil) -> SwimSession {
        let base = AnalysisResult.demo
        let result = AnalysisResult(
            id: UUID(), score: 72, grade: "C",
            strokeCount: base.strokeCount, kickRatePerMin: base.kickRatePerMin,
            strokeAsymmetry: base.strokeAsymmetry, frameCount: base.frameCount,
            sampledFrames: base.sampledFrames, fps: base.fps,
            issues: base.issues, tips: base.tips,
            analyzedAt: analyzedAt, durationSeconds: durationSeconds)
        let session = SwimSession(result: result)
        session.name = name
        session.swimmer = swimmer
        session.notes = notes
        return session
    }

    /// A spread that exercises every column: escaping, formula injection,
    /// the modern duration column, the legacy blob fallback, and sorting.
    private func makeMixedLibrary() -> [SwimSession] {
        let modern = makeSession(name: "Taper, \"A\" set", swimmer: "Maya",
                                 notes: "felt strong",
                                 analyzedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                 durationSeconds: 62.5)
        let injected = makeSession(name: "=1+1", swimmer: "@SUM(A1:A9)",
                                   analyzedAt: Date(timeIntervalSince1970: 1_600_000_000),
                                   durationSeconds: 52)
        let legacy = makeSession(name: "Legacy",
                                 analyzedAt: Date(timeIntervalSince1970: 1_500_000_000),
                                 durationSeconds: 62.5)
        legacy.durationSeconds = 0          // pre-v1.43.0 shape: blob still holds it
        let unknown = makeSession(name: "Unknown",
                                  analyzedAt: Date(timeIntervalSince1970: 1_400_000_000),
                                  durationSeconds: nil)
        return [legacy, modern, unknown, injected]   // deliberately unsorted
    }

    // MARK: - Byte parity with the model-backed path

    func testSnapshotCSVIsByteIdenticalToModelBackedCSV() {
        // Arrange
        let sessions = makeMixedLibrary()

        // Act
        let fromModels = SessionCSV.csv(from: sessions)
        let fromSnapshots = SessionCSV.csv(snapshots: sessions.map { SessionSnapshot(session: $0) })

        // Assert
        XCTAssertEqual(fromSnapshots, fromModels)
        XCTAssertEqual(Data(fromSnapshots.utf8), Data(fromModels.utf8))
        XCTAssertEqual(fromSnapshots.split(separator: "\n").count, 5,
                       "header plus four session rows, otherwise the fixture is not exercised")
    }

    func testSnapshotArchiveIsByteIdenticalToModelBackedArchive() throws {
        // Arrange — pinned `now` so only the session mapping can differ
        let sessions = makeMixedLibrary()
        let events = [
            DrillPracticeEvent(drillID: "fist-drill", date: Date(timeIntervalSince1970: 1_700_000_000)),
            DrillPracticeEvent(drillID: "catch-up", date: Date(timeIntervalSince1970: 1_600_000_000)),
        ]
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        // Act
        let fromModels = try SessionExport.archiveData(from: sessions, practice: events, now: now)
        let fromSnapshots = try SessionExport.archiveData(
            snapshots: sessions.map { SessionSnapshot(session: $0) },
            practice: events.map { PracticeSnapshot(event: $0) },
            now: now)

        // Assert
        XCTAssertEqual(fromSnapshots, fromModels)
    }

    func testEmptyLibrarySnapshotMatchesModelBackedOutput() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(SessionCSV.csv(snapshots: []), SessionCSV.csv(from: []))
        XCTAssertEqual(try SessionExport.archiveData(snapshots: [], now: now),
                       try SessionExport.archiveData(from: [], now: now))
    }

    // MARK: - Capture semantics

    func testSnapshotCopiesEveryExportedField() {
        // Arrange
        let session = makeSession(name: "Threshold", swimmer: "Maya", notes: "felt strong",
                                  analyzedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                  durationSeconds: 62.5)

        // Act
        let snapshot = SessionSnapshot(session: session)

        // Assert
        XCTAssertEqual(snapshot.analyzedAt, session.analyzedAt)
        XCTAssertEqual(snapshot.name, "Threshold")
        XCTAssertEqual(snapshot.swimmer, "Maya")
        XCTAssertEqual(snapshot.notes, "felt strong")
        XCTAssertEqual(snapshot.score, session.score)
        XCTAssertEqual(snapshot.grade, session.grade)
        XCTAssertEqual(snapshot.issueNames, session.issueNames)
        XCTAssertEqual(snapshot.strokeCount, session.strokeCount)
        XCTAssertEqual(snapshot.kickRatePerMin, session.kickRatePerMin)
        XCTAssertEqual(snapshot.durationSeconds, 62.5)
    }

    func testSnapshotIsDetachedFromTheModelAfterCapture() {
        // Arrange — the property that makes the background build safe: once
        // captured, the export never reads the model again.
        let session = makeSession(name: "Before", swimmer: "Maya",
                                  analyzedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                  durationSeconds: 62.5)
        let snapshot = SessionSnapshot(session: session)
        let captured = SessionCSV.csv(snapshots: [snapshot])

        // Act — mutate the model the way the UI would while a build is in flight
        session.name = "After"
        session.score = 1
        session.issueNames = ["mutated"]
        session.durationSeconds = 999

        // Assert
        XCTAssertEqual(SessionCSV.csv(snapshots: [snapshot]), captured)
        XCTAssertTrue(captured.contains("Before"))
        XCTAssertFalse(captured.contains("After"))
    }

    func testModernRowSnapshotsWithoutDecodingTheResultBlob() {
        // Arrange — v1.45.5's win must survive the snapshot layer: a row with
        // a stored duration never touches the external-storage blob.
        let session = makeSession(name: "Threshold",
                                  analyzedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                  durationSeconds: 62.5)
        session.resultData = Data("{ not json".utf8)
        XCTAssertNil(session.decoded(),
                     "blob must be undecodable, otherwise this test proves nothing")

        // Act
        let snapshot = SessionSnapshot(session: session)

        // Assert — no fallback captured, and the row still carries the duration
        XCTAssertNil(snapshot.legacyDurationSeconds)
        XCTAssertTrue(SessionCSV.csv(snapshots: [snapshot]).hasSuffix(",48,52,62.5\n"))
    }

    func testLegacyRowSnapshotRecoversDurationFromTheBlob() {
        // Arrange — the pre-v1.43.0 shape: column at its 0 sentinel
        let session = makeSession(name: "Legacy", durationSeconds: 62.5)
        session.durationSeconds = 0

        // Act
        let snapshot = SessionSnapshot(session: session)

        // Assert
        XCTAssertEqual(snapshot.legacyDurationSeconds, 62.5)
        XCTAssertTrue(SessionCSV.csv(snapshots: [snapshot]).hasSuffix(",48,52,62.5\n"))
    }

    func testPracticeSnapshotCopiesDateAndDrill() {
        // Arrange
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let event = DrillPracticeEvent(drillID: "fist-drill", date: date)

        // Act
        let snapshot = PracticeSnapshot(event: event)

        // Assert
        XCTAssertEqual(snapshot, PracticeSnapshot(date: date, drillID: "fist-drill"))
    }

    // MARK: - Off-main writer

    func testWriterProducesTheSameBytesAtTheDocumentedFilenames() async throws {
        // Arrange
        let sessions = makeMixedLibrary().map { SessionSnapshot(session: $0) }

        // Act
        let csvURL = try await TrainingLogWriter.writeCSV(sessions: sessions)
        let jsonURL = try await TrainingLogWriter.writeArchive(sessions: sessions, practice: [])

        // Assert — same names the pre-async export shipped, same contents
        XCTAssertEqual(csvURL.lastPathComponent, "swimcoach-training-log.csv")
        XCTAssertEqual(jsonURL.lastPathComponent, "swimcoach-training-log.json")
        XCTAssertEqual(try Data(contentsOf: csvURL),
                       Data(SessionCSV.csv(snapshots: sessions).utf8))
        XCTAssertFalse(try Data(contentsOf: jsonURL).isEmpty)
    }
}
