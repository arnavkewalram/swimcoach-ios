import SwiftUI

/// Fixed-format shareable report card (1080×1350 @1x render target) —
/// the session summary in the editorial print style, for sending to a
/// coach or teammate. Render via `ReportCardView.render(result:)`.
struct ReportCardView: View {
    let result: AnalysisResult
    /// Chronological recent scores ending with this session — draws the
    /// PROGRESS sparkline when there are at least two points.
    var trendScores: [Int]? = nil
    var newBest: Bool = false

    static let size = CGSize(width: 540, height: 675)   // rendered @2x → 1080×1350

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Masthead
            HStack(alignment: .firstTextBaseline) {
                Text("SwimCoach")
                    .font(.grotesk(28, .bold))
                    .foregroundStyle(DS.ink)
                Spacer()
                Text(result.analyzedAt.formatted(date: .abbreviated, time: .omitted).uppercased())
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 11))
                    .tracking(1.4)
                    .foregroundStyle(DS.inkTertiary)
            }
            .padding(.bottom, 6)

            laneRule
                .padding(.bottom, 22)

            // Score block
            Text("TECHNIQUE SCORE")
                .font(.custom(GroteskWeight.medium.postScriptName, size: 11))
                .tracking(1.8)
                .foregroundStyle(DS.inkTertiary)
                .padding(.bottom, 2)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(result.score)")
                    .font(.grotesk(76, .bold))
                    .foregroundStyle(DS.ink)
                Text(result.grade)
                    .font(.grotesk(30, .bold))
                    .foregroundStyle(DS.gradeColor(result.grade))
                if newBest {
                    Text("NEW BEST")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                        .tracking(1.4)
                        .foregroundStyle(DS.severityMinor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .stroke(DS.severityMinor.opacity(0.55), lineWidth: 1))
                        .offset(y: -6)
                }
            }
            .padding(.bottom, 16)

            // Metrics line
            HStack(spacing: 22) {
                metric("\(result.strokeCount)", "STROKES")
                if let spm = result.strokeRatePerMin {
                    metric(String(format: "%.0f", spm), "STROKES/MIN")
                }
                metric(String(format: "%.0f", result.kickRatePerMin), "KICKS/MIN")
                metric(String(format: "%.0f%%", result.strokeAsymmetry * 100), "ASYMMETRY")
            }
            .padding(.bottom, 22)

            // Progress sparkline (needs >= 2 points)
            if let trend = trendScores, trend.count >= 2 {
                HStack(alignment: .firstTextBaseline) {
                    Text("PROGRESS")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 11))
                        .tracking(1.8)
                        .foregroundStyle(DS.inkTertiary)
                    Spacer()
                    Text("LAST \(trend.count) SESSIONS")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                        .tracking(1.2)
                        .foregroundStyle(DS.inkTertiary)
                }
                .padding(.bottom, 6)
                // Flexible height: the chart absorbs vertical slack so the
                // fixed-size card stays tight regardless of issue count.
                Sparkline(values: trend)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 40, maxHeight: 84)
                    .padding(.bottom, 18)
            }

            laneRule
                .padding(.bottom, 14)

            // Issues
            Text("ISSUES DETECTED")
                .font(.custom(GroteskWeight.medium.postScriptName, size: 11))
                .tracking(1.8)
                .foregroundStyle(DS.inkTertiary)
                .padding(.bottom, 8)

            if result.issues.isEmpty {
                Text("None — excellent technique.")
                    .font(.system(size: 14))
                    .foregroundStyle(DS.inkSecondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(result.issues.prefix(5), id: \.name) { issue in
                        HStack(spacing: 10) {
                            Rectangle()
                                .fill(severityColor(issue))
                                .frame(width: 3, height: 16)
                            Text(issue.displayName)
                                .font(.grotesk(16, .medium))
                                .foregroundStyle(DS.ink)
                            Spacer()
                            Text(issue.severity.rawValue.uppercased())
                                .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                                .tracking(1.2)
                                .foregroundStyle(severityColor(issue))
                        }
                    }
                }
            }

            // Coach's focus — the top issue's cue fills what used to be a
            // dead quarter of the card with the one thing to work on next.
            if let focusTip = result.issues.first?.tip ?? result.tips.first {
                Spacer(minLength: 14)
                VStack(alignment: .leading, spacing: 5) {
                    Text("COACH'S FOCUS")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 11))
                        .tracking(1.8)
                        .foregroundStyle(DS.inkTertiary)
                    Text(focusTip)
                        .font(.grotesk(15, .medium))
                        .foregroundStyle(DS.ink)
                        .lineSpacing(3)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 13)
                .overlay(alignment: .leading) {
                    Rectangle().fill(DS.accent).frame(width: 3)
                }
            }

            Spacer(minLength: 14)

            laneRule
                .padding(.bottom, 10)
            HStack {
                Text("ON-DEVICE BIOMECHANICS ANALYSIS")
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                    .tracking(1.6)
                    .foregroundStyle(DS.inkTertiary)
                Spacer()
                Image(systemName: "figure.pool.swim")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.accent)
            }
        }
        .padding(36)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(DS.background)
    }

    private var laneRule: some View {
        VStack(spacing: 3) {
            Rectangle().fill(DS.border).frame(height: 1)
            Rectangle().fill(DS.border).frame(height: 1)
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.grotesk(22, .bold))
                .foregroundStyle(DS.ink)
            Text(label)
                .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                .tracking(1.2)
                .foregroundStyle(DS.inkTertiary)
        }
    }

    private func severityColor(_ issue: TechniqueIssue) -> Color {
        switch issue.severity {
        case .major:    return DS.severityMajor
        case .moderate: return DS.severityModerate
        case .minor:    return DS.severityMinor
        }
    }

    /// Render the report card to a shareable image (2x scale → 1080×1350).
    @MainActor
    static func render(result: AnalysisResult,
                       trendScores: [Int]? = nil,
                       newBest: Bool = false) -> UIImage? {
        let renderer = ImageRenderer(content: ReportCardView(
            result: result, trendScores: trendScores, newBest: newBest))
        renderer.scale = 2
        return renderer.uiImage
    }
}

/// Full-screen presentation of the report card (the `.report` route):
/// scaled preview plus a toolbar share, mirroring the Results toolbar
/// conventions so the share affordance sits above the fold.
struct ReportScreen: View {
    let result: AnalysisResult
    var trendScores: [Int]? = nil
    var newBest: Bool = false
    @State private var reportImage: UIImage? = nil

    var body: some View {
        ScrollView {
            ReportCardView(result: result, trendScores: trendScores, newBest: newBest)
                .scaleEffect(0.68, anchor: .top)
        }
        .background(DS.ink.opacity(0.06))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Report")
                    .font(.grotesk(17, .medium))
                    .foregroundStyle(DS.ink)
            }
            if let reportImage {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: Image(uiImage: reportImage),
                        preview: SharePreview("SwimCoach report — \(result.score)/100",
                                              image: Image(uiImage: reportImage))
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(DS.accent)
                    }
                    .accessibilityLabel("Share report card")
                }
            }
        }
        .toolbarBackground(DS.background, for: .navigationBar)
        .onAppear {
            if reportImage == nil {
                reportImage = ReportCardView.render(
                    result: result, trendScores: trendScores, newBest: newBest)
            }
        }
    }
}
