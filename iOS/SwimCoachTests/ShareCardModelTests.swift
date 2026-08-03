import XCTest
@testable import SwimCoach

final class ShareCardModelTests: XCTestCase {

    // MARK: - Fixtures

    private func makeResult(score: Int = 72, grade: String = "C",
                            strokeCount: Int = 48,
                            issues: [TechniqueIssue] = [],
                            durationSeconds: Double? = 60,
                            analyzedAt: Date = Date(timeIntervalSince1970: 1_752_000_000)) -> AnalysisResult {
        AnalysisResult(id: UUID(), score: score, grade: grade,
                       strokeCount: strokeCount, kickRatePerMin: 50,
                       strokeAsymmetry: 0.12, frameCount: 500, sampledFrames: 550,
                       fps: 30, issues: issues, tips: [], analyzedAt: analyzedAt,
                       durationSeconds: durationSeconds)
    }

    private func makeIssue(_ displayName: String,
                           _ severity: TechniqueIssue.Severity) -> TechniqueIssue {
        TechniqueIssue(name: displayName.lowercased().replacingOccurrences(of: " ", with: "_"),
                       displayName: displayName, severity: severity,
                       observedValue: 0.8, threshold: 0.45,
                       description: "", tip: "")
    }

    // MARK: - Score block

    func testScoreGradeAndVerdictFormatting() {
        let model = ShareCardModel(result: makeResult(score: 88, grade: "B"))

        XCTAssertEqual(model.scoreText, "88")
        XCTAssertEqual(model.grade, "B")
        XCTAssertEqual(model.verdict, "Good form")
    }

    func testVerdictCoversEveryGrade() {
        XCTAssertEqual(ShareCardModel.verdict(for: "A"), "Excellent technique")
        XCTAssertEqual(ShareCardModel.verdict(for: "B"), "Good form")
        XCTAssertEqual(ShareCardModel.verdict(for: "C"), "Room to improve")
        XCTAssertEqual(ShareCardModel.verdict(for: "D"), "Needs work")
        XCTAssertEqual(ShareCardModel.verdict(for: "F"), "Keep practicing")
    }

    // MARK: - Swimmer tag + session name

    func testSwimmerTagUppercasesAndTrims() {
        let model = ShareCardModel(result: makeResult(), swimmer: "  maya ")

        XCTAssertEqual(model.swimmerTag, "MAYA")
    }

    func testSwimmerTagAndNameNilWhenUnset() {
        let model = ShareCardModel(result: makeResult(), swimmer: "   ", sessionName: "")

        XCTAssertNil(model.swimmerTag)
        XCTAssertNil(model.sessionName)
    }

    func testSessionNameKeptVerbatimWhenSet() {
        let model = ShareCardModel(result: makeResult(), sessionName: "Tuesday threshold")

        XCTAssertEqual(model.sessionName, "Tuesday threshold")
    }

    // MARK: - Metrics

    func testDurationAndStrokeRateFormatting() {
        let model = ShareCardModel(result: makeResult(strokeCount: 45, durationSeconds: 90))

        XCTAssertEqual(model.durationText, "1:30")
        XCTAssertEqual(model.strokesText, "45")
        XCTAssertEqual(model.strokeRateText, "30")   // 45 strokes over 1.5 min
    }

    func testLegacySessionWithoutDurationDropsRateAndDuration() {
        let model = ShareCardModel(result: makeResult(durationSeconds: nil))

        XCTAssertNil(model.durationText)
        XCTAssertNil(model.strokeRateText)
    }

    func testStrokesTextShowsDashWhenNoneCounted() {
        let model = ShareCardModel(result: makeResult(strokeCount: 0))

        XCTAssertEqual(model.strokesText, "–")
    }

    func testDateTextUsesAbbreviatedUppercasedDate() {
        let date = Date(timeIntervalSince1970: 1_752_000_000)

        let model = ShareCardModel(result: makeResult(analyzedAt: date))

        XCTAssertEqual(model.dateText,
                       date.formatted(date: .abbreviated, time: .omitted).uppercased())
    }

    // MARK: - Top issues

    func testTopIssuesOrderedBySeverityAndCappedAtThree() {
        let result = makeResult(issues: [
            makeIssue("Low Kick Rate", .minor),
            makeIssue("Body Sag", .major),
            makeIssue("Left Elbow Collapse", .moderate),
            makeIssue("Crossover Entry", .major),
        ])

        let model = ShareCardModel(result: result)

        XCTAssertEqual(model.topIssues.count, 3)
        XCTAssertEqual(model.topIssues.map(\.name),
                       ["Body Sag", "Crossover Entry", "Left Elbow Collapse"])
        XCTAssertEqual(model.topIssues.first?.severity, .major)
    }

    func testTopIssuesEmptyForCleanSession() {
        let model = ShareCardModel(result: makeResult(issues: []))

        XCTAssertTrue(model.topIssues.isEmpty)
    }

    // MARK: - Invalidation (model equality drives the cached-card re-render)

    func testModelEqualityDetectsSwimmerEdit() {
        let result = makeResult()
        let before = ShareCardModel(result: result, swimmer: "Maya", sessionName: "Tuesday threshold")
        let after = ShareCardModel(result: result, swimmer: "Alex", sessionName: "Tuesday threshold")

        XCTAssertNotEqual(before, after)
    }

    func testModelEqualityDetectsSessionNameEdit() {
        let result = makeResult()
        let before = ShareCardModel(result: result, swimmer: "Maya", sessionName: "Tuesday threshold")
        let after = ShareCardModel(result: result, swimmer: "Maya", sessionName: "Wednesday sprint")

        XCTAssertNotEqual(before, after)
    }

    func testModelEqualityUnchangedByCosmeticWhitespaceEdit() {
        // Whitespace-only edits normalize to the same card content — no
        // spurious re-render.
        let result = makeResult()
        let before = ShareCardModel(result: result, swimmer: "Maya", sessionName: "Tuesday threshold")
        let after = ShareCardModel(result: result, swimmer: "  Maya ", sessionName: " Tuesday threshold ")

        XCTAssertEqual(before, after)
    }

    func testModelEqualityUnchangedWhenInputsIdentical() {
        let result = makeResult()

        XCTAssertEqual(ShareCardModel(result: result, swimmer: "Maya", sessionName: "Tuesday threshold"),
                       ShareCardModel(result: result, swimmer: "Maya", sessionName: "Tuesday threshold"))
    }

    // MARK: - Share metadata

    func testPreviewTitleContainsScoreAndGrade() {
        let model = ShareCardModel(result: makeResult(score: 91, grade: "A"))

        XCTAssertEqual(model.previewTitle, "SwimCoach session — 91/100 (A)")
    }

    // MARK: - Render

    @MainActor
    func testRenderProducesSquareSocialImage() {
        let image = ShareCardView.render(model: ShareCardModel(
            result: .demo, swimmer: "Maya", sessionName: "Tuesday threshold"))

        XCTAssertNotNil(image)
        // 480×480 @3x → 1440×1440 square
        XCTAssertEqual((image?.size.width ?? 0) * (image?.scale ?? 0), 1440)
        XCTAssertEqual((image?.size.height ?? 0) * (image?.scale ?? 0), 1440)
    }
}
