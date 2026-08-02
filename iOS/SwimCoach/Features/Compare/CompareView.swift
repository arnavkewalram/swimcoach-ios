import SwiftUI

/// Side-by-side progress view between an earlier and a later session.
struct CompareView: View {
    let earlier: AnalysisResult
    let later: AnalysisResult

    private var deltas: [IssueDelta] {
        SessionComparison.issueDeltas(from: earlier, to: later)
    }

    private var scoreDelta: Int { later.score - earlier.score }

    var body: some View {
        ZStack {
            DS.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Score head-to-head ────────────────────────────────
                    HStack(spacing: 0) {
                        scoreColumn(label: "EARLIER", result: earlier)
                        Rectangle().fill(DS.border).frame(width: 1, height: 88)
                        scoreColumn(label: "LATER", result: later)
                    }
                    .padding(.vertical, 18)
                    .glassCard()
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                    // Verdict line
                    HStack(spacing: 8) {
                        Image(systemName: scoreDelta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.footnote.weight(.semibold))
                            .accessibilityHidden(true)
                        Text(verdictLine)
                            .font(.grotesk(14, .medium))
                    }
                    .foregroundStyle(scoreDelta > 0 ? DS.severityMinor :
                                     scoreDelta < 0 ? DS.severityModerate : DS.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)

                    // ── Metrics ───────────────────────────────────────────
                    SectionHeader(title: "Metrics")
                        .padding(.bottom, 10)
                    VStack(spacing: 0) {
                        metricRow("Strokes",
                                  from: "\(earlier.strokeCount)", to: "\(later.strokeCount)")
                        Rectangle().fill(DS.border).frame(height: 1).padding(.leading, 16)
                        metricRow("Kicks / min",
                                  from: String(format: "%.0f", earlier.kickRatePerMin),
                                  to: String(format: "%.0f", later.kickRatePerMin))
                        Rectangle().fill(DS.border).frame(height: 1).padding(.leading, 16)
                        metricRow("Asymmetry",
                                  from: String(format: "%.0f%%", earlier.strokeAsymmetry * 100),
                                  to: String(format: "%.0f%%", later.strokeAsymmetry * 100))
                    }
                    .glassCard()
                    .padding(.bottom, 24)

                    // ── Issues ────────────────────────────────────────────
                    SectionHeader(title: "Issues")
                        .padding(.bottom, 10)
                    if deltas.isEmpty {
                        Text("No issues detected in either session.")
                            .font(.footnote)
                            .foregroundStyle(DS.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .glassCard()
                    } else {
                        VStack(spacing: 8) {
                            ForEach(deltas) { delta in
                                deltaRow(delta)
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
        }
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Compare")
                    .font(.grotesk(17, .medium))
                    .foregroundStyle(DS.ink)
            }
        }
        .toolbarBackground(DS.background, for: .navigationBar)
    }

    private var verdictLine: String {
        if scoreDelta > 0 { return "Up \(scoreDelta) points" }
        if scoreDelta < 0 { return "Down \(-scoreDelta) points" }
        return "Same score"
    }

    private func scoreColumn(label: String, result: AnalysisResult) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.sectionLabel)
                .tracking(1.4)
                .foregroundStyle(DS.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(result.score)")
                    .font(.grotesk(40, .bold))
                    .foregroundStyle(DS.ink)
                Text(result.grade)
                    .font(.grotesk(18, .bold))
                    .foregroundStyle(DS.gradeColor(result.grade))
            }
            Text(result.analyzedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(DS.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func metricRow(_ label: String, from: String, to: String) -> some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundStyle(DS.inkSecondary)
            Spacer()
            Text(from)
                .font(.grotesk(15, .medium))
                .foregroundStyle(DS.inkTertiary)
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(DS.inkTertiary)
                .accessibilityHidden(true)
            Text(to)
                .font(.grotesk(15, .bold))
                .foregroundStyle(DS.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func deltaRow(_ delta: IssueDelta) -> some View {
        HStack(spacing: 12) {
            Text(delta.displayName)
                .font(.grotesk(14, .medium))
                .foregroundStyle(DS.ink)
                .lineLimit(2)
            Spacer()
            if let f = delta.from, let t = delta.to {
                Text("\(Int(f * 100))→\(Int(t * 100))")
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 11))
                    .foregroundStyle(DS.inkTertiary)
            }
            verdictChip(delta.verdict)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .glassCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(delta.displayName): \(verdictSpoken(delta.verdict))")
    }

    private func verdictChip(_ verdict: IssueDelta.Verdict) -> some View {
        Text(verdict.rawValue)
            .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
            .tracking(1.2)
            .foregroundStyle(verdictColor(verdict))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(verdictColor(verdict).opacity(0.55), lineWidth: 1))
    }

    private func verdictColor(_ verdict: IssueDelta.Verdict) -> Color {
        switch verdict {
        case .improved, .resolved: return DS.severityMinor
        case .worsened, .new:      return DS.severityMajor
        case .unchanged:           return DS.inkTertiary
        }
    }

    private func verdictSpoken(_ verdict: IssueDelta.Verdict) -> String {
        switch verdict {
        case .new: return "newly detected"
        case .resolved: return "resolved"
        case .improved: return "improved"
        case .worsened: return "worse"
        case .unchanged: return "unchanged"
        }
    }
}
