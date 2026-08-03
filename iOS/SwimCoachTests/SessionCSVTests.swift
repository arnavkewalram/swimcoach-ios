import XCTest
@testable import SwimCoach

final class SessionCSVTests: XCTestCase {

    private let expectedHeader =
        "date,name,swimmer,score,grade,issues,strokeCount,kickRatePerMin,durationSeconds"

    private func makeSession(name: String = "",
                             swimmer: String = "",
                             analyzedAt: Date = Date(),
                             durationSeconds: Double? = nil) -> SwimSession {
        let base = AnalysisResult.demo
        let result = AnalysisResult(
            id: UUID(), score: 72, grade: "C",
            strokeCount: base.strokeCount, kickRatePerMin: base.kickRatePerMin,
            strokeAsymmetry: base.strokeAsymmetry, frameCount: base.frameCount,
            sampledFrames: base.sampledFrames, fps: base.fps,
            issues: base.issues, tips: base.tips,
            analyzedAt: analyzedAt,
            durationSeconds: durationSeconds)
        let session = SwimSession(result: result)
        session.name = name
        session.swimmer = swimmer
        return session
    }

    func testHeaderListsSpecColumnsInOrder() {
        // Arrange
        let sessions = [makeSession(name: "Threshold")]

        // Act
        let lines = SessionCSV.csv(from: sessions).split(separator: "\n")

        // Assert
        XCTAssertEqual(lines.first.map(String.init), expectedHeader)
        XCTAssertEqual(lines.count, 2, "one header row plus one session row")
    }

    func testEmptyListYieldsHeaderOnly() {
        // Arrange — no sessions

        // Act
        let csv = SessionCSV.csv(from: [])

        // Assert
        XCTAssertEqual(csv, expectedHeader + "\n")
    }

    func testEscapesNameContainingCommaAndQuote() {
        // Arrange
        let session = makeSession(name: "Taper, \"A\" set", swimmer: "Maya")

        // Act
        let row = String(SessionCSV.csv(from: [session]).split(separator: "\n")[1])

        // Assert — field is quoted and the embedded quotes are doubled
        XCTAssertTrue(row.contains("\"Taper, \"\"A\"\" set\",Maya"),
                      "expected escaped name field in: \(row)")
        XCTAssertFalse(row.contains(",Taper, \"A\" set,"),
                       "raw name must not leak into the row unescaped")
    }

    func testEscapeQuotesOnlyWhenNeeded() {
        XCTAssertEqual(SessionCSV.escape("plain"), "plain")
        XCTAssertEqual(SessionCSV.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(SessionCSV.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(SessionCSV.escape("line\nbreak"), "\"line\nbreak\"")
    }

    func testRowsSortedNewestFirst() {
        // Arrange — deliberately shuffled input order
        let sessions = [
            makeSession(name: "Middle", analyzedAt: Date(timeIntervalSince1970: 2_000)),
            makeSession(name: "Latest", analyzedAt: Date(timeIntervalSince1970: 3_000)),
            makeSession(name: "Oldest", analyzedAt: Date(timeIntervalSince1970: 1_000)),
        ]

        // Act
        let lines = SessionCSV.csv(from: sessions).split(separator: "\n")

        // Assert
        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines[1].contains("Latest"))
        XCTAssertTrue(lines[2].contains("Middle"))
        XCTAssertTrue(lines[3].contains("Oldest"))
    }

    func testRowCarriesAllColumnsWithISODateAndTrimmedNumbers() {
        // Arrange — fixed epoch: 2023-11-14T22:13:20Z
        let session = makeSession(name: "Threshold", swimmer: "Maya",
                                  analyzedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                  durationSeconds: 62.5)

        // Act
        let row = String(SessionCSV.csv(from: [session]).split(separator: "\n")[1])

        // Assert — demo fixture: 48 strokes, kick rate 52.0 (trimmed to "52")
        XCTAssertEqual(row,
            "2023-11-14T22:13:20Z,Threshold,Maya,72,C," +
            "body_sag; left_elbow_collapse; low_kick_rate,48,52,62.5")
    }

    func testLegacySessionWithoutDurationYieldsEmptyLastField() {
        // Arrange
        let session = makeSession(name: "Legacy", durationSeconds: nil)

        // Act
        let row = String(SessionCSV.csv(from: [session]).split(separator: "\n")[1])

        // Assert — kick rate then a trailing empty duration field
        XCTAssertTrue(row.hasSuffix(",48,52,"), "expected empty duration in: \(row)")
    }
}
