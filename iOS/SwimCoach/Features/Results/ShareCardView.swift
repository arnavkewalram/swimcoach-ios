import SwiftUI

/// Square social share card (480×480 pt, rendered @3x → 1440×1440 px) —
/// the session headline in the editorial meet-sheet style, for posting or
/// sending after a swim. All strings come pre-formatted on
/// `ShareCardModel`; render via `ShareCardView.render(model:)`.
struct ShareCardView: View {
    let model: ShareCardModel

    static let size = CGSize(width: 480, height: 480)   // rendered @3x → 1440×1440

    private var gradeColor: Color { DS.gradeColor(model.grade) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Masthead
            HStack(alignment: .firstTextBaseline) {
                Text("SwimCoach")
                    .font(.grotesk(24, .bold))
                    .foregroundStyle(DS.ink)
                Spacer()
                Text(model.dateText)
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                    .tracking(1.4)
                    .foregroundStyle(DS.inkTertiary)
            }
            .padding(.bottom, 6)

            laneRule

            Spacer(minLength: 12)

            // Swimmer tag + session name
            if model.swimmerTag != nil || model.sessionName != nil {
                HStack(spacing: 8) {
                    if let tag = model.swimmerTag {
                        Text(tag)
                            .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                            .tracking(1.2)
                            .foregroundStyle(DS.accent)
                            .fixedSize()
                    }
                    if let name = model.sessionName {
                        Text(name)
                            .font(.grotesk(14, .medium))
                            .foregroundStyle(DS.inkSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.bottom, 12)
            }

            // Score block
            Text("TECHNIQUE SCORE")
                .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                .tracking(1.8)
                .foregroundStyle(DS.inkTertiary)
                .padding(.bottom, 2)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(model.scoreText)
                    .font(.grotesk(60, .bold))
                    .foregroundStyle(DS.ink)
                Text(model.grade)
                    .font(.grotesk(26, .bold))
                    .foregroundStyle(gradeColor)
            }
            Text(model.verdict.uppercased())
                .font(.custom(GroteskWeight.medium.postScriptName, size: 11))
                .tracking(1.8)
                .foregroundStyle(gradeColor)

            Spacer(minLength: 14)

            // Metrics line
            HStack(spacing: 26) {
                if let duration = model.durationText {
                    metric(duration, "DURATION")
                }
                metric(model.strokesText, "STROKES")
                if let rate = model.strokeRateText {
                    metric(rate, "STROKES/MIN")
                }
            }

            Spacer(minLength: 14)

            laneRule
                .padding(.bottom, 10)

            // Top issues
            Text(model.topIssues.isEmpty ? "CLEAN TECHNIQUE" : "TOP ISSUES")
                .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                .tracking(1.8)
                .foregroundStyle(DS.inkTertiary)
                .padding(.bottom, 8)

            if model.topIssues.isEmpty {
                Text("None detected — excellent technique.")
                    .font(.system(size: 14))
                    .foregroundStyle(DS.inkSecondary)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(model.topIssues, id: \.name) { line in
                        HStack(spacing: 10) {
                            Rectangle()
                                .fill(severityColor(line.severity))
                                .frame(width: 3, height: 14)
                            Text(line.name)
                                .font(.grotesk(15, .medium))
                                .foregroundStyle(DS.ink)
                            Spacer()
                            Text(line.severity.rawValue.uppercased())
                                .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                                .tracking(1.2)
                                .foregroundStyle(severityColor(line.severity))
                        }
                    }
                }
            }

            Spacer(minLength: 14)

            laneRule
                .padding(.bottom, 9)
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
        .padding(32)
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

    private func severityColor(_ severity: TechniqueIssue.Severity) -> Color {
        switch severity {
        case .major:    return DS.severityMajor
        case .moderate: return DS.severityModerate
        case .minor:    return DS.severityMinor
        }
    }

    /// Render the card to a shareable image (3x scale → 1440×1440 px).
    @MainActor
    static func render(model: ShareCardModel) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(model: model))
        renderer.scale = 3
        return renderer.uiImage
    }
}
