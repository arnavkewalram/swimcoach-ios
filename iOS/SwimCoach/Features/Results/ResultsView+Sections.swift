import SwiftUI

// MARK: - ResultsView · score panel, quality notes, metrics, footer
//
// Moved verbatim from ResultsView.swift in the 1.36–1.42 code-health pass.
// State lives on ResultsView; these members only read it.

extension ResultsView {

    // MARK: - Score panel

    var gradeColor: Color { DS.gradeColor(result.grade) }

    var verdict: String { ShareCardModel.verdict(for: result.grade) }

    var scorePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TECHNIQUE SCORE")
                .font(.sectionLabel)
                .tracking(1.6)
                .foregroundStyle(DS.inkTertiary)
                .padding(.bottom, 6)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(Int(animatedScore))")
                    .font(.grotesk(84, .bold))
                    .foregroundStyle(DS.ink)
                    .contentTransition(.numericText())
                Text(result.grade)
                    .font(.grotesk(32, .bold))
                    .foregroundStyle(gradeColor)
                Spacer()
            }
            .padding(.bottom, 10)

            // Score rule — flat 0–100 bar in the grade color
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(DS.border)
                    Rectangle()
                        .fill(gradeColor)
                        .frame(width: geo.size.width * animatedScore / 100)
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
            .padding(.bottom, 12)

            HStack {
                Text(verdict.uppercased())
                    .font(.grotesk(13, .medium))
                    .tracking(1.8)
                    .foregroundStyle(gradeColor)
                Spacer()
                if isNewBest {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.to.line")
                            .font(.system(size: 9, weight: .semibold))
                            .accessibilityHidden(true)
                        Text("NEW BEST")
                            .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                            .tracking(1.4)
                    }
                    .foregroundStyle(DS.severityMinor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(DS.severityMinor.opacity(0.55), lineWidth: 1))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Technique score \(result.score) out of 100, grade \(result.grade). \(verdict)." +
                            (isNewBest ? " New personal best." : ""))
    }

    // MARK: - Quality note

    func qualityNote(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(color)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .lineSpacing(2)
                .foregroundStyle(DS.inkSecondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle().fill(color.opacity(0.7)).frame(width: 3)
        }
        .background(color.opacity(0.05))
    }

    // MARK: - Metrics

    var metricsStrip: some View {
        HStack(spacing: 0) {
            metric(value: result.strokeCount > 0 ? "\(result.strokeCount)" : "–",
                   label: "STROKES")
            metricDivider
            if let spm = result.strokeRatePerMin {
                metric(value: String(format: "%.0f", spm), label: "STROKES/MIN")
                metricDivider
            }
            metric(value: result.kickRatePerMin > 0 ? String(format: "%.0f", result.kickRatePerMin) : "–",
                   label: "KICKS/MIN")
            metricDivider
            metric(value: result.strokeCount > 0 ? String(format: "%.0f%%", result.strokeAsymmetry * 100) : "–",
                   label: "ASYMMETRY",
                   valueColor: result.strokeAsymmetry > 0.3 ? DS.severityModerate : DS.ink)
        }
        .padding(.vertical, 8)
    }

    private var metricDivider: some View {
        Rectangle().fill(DS.border).frame(width: 1, height: 40)
    }

    private func metric(value: String, label: String, valueColor: Color = DS.ink) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.grotesk(24, .bold))
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.statUnit)
                .tracking(1.2)
                .foregroundStyle(DS.inkTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Footer

    var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: isSaved ? "checkmark" : "exclamationmark.triangle")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSaved ? DS.severityMinor : DS.severityModerate)
                    .accessibilityHidden(true)
                Text(isSaved
                     ? "Session saved"
                     : "Session not saved — a storage error occurred")
                    .font(.footnote)
                    .foregroundStyle(isSaved ? DS.inkSecondary : DS.severityModerate)
            }
            .frame(maxWidth: .infinity)

            Button {
                router.popToRoot()
            } label: {
                SecondaryButtonLabel(title: "Done")
            }
            .buttonStyle(ScaleButtonStyle())
        }
    }
}
