import SwiftUI

/// Per-issue intensity bands over the swim's duration — shows WHEN each
/// detected fault flared. Tapping a band cell seeks the video there.
struct IssueTimelineStrip: View {
    let windows: [IssueWindow]
    let issues: [TechniqueIssue]
    let onSelect: (Double) -> Void

    private var span: (start: Double, end: Double)? {
        guard let first = windows.first, let last = windows.last else { return nil }
        return (first.start, max(last.end, first.start + 0.001))
    }

    var body: some View {
        if let span {
            VStack(alignment: .leading, spacing: 8) {
                Text("WHEN IT HAPPENED")
                    .font(.sectionLabel)
                    .tracking(1.6)
                    .foregroundStyle(DS.inkTertiary)

                VStack(spacing: 6) {
                    ForEach(issues, id: \.name) { issue in
                        if let index = FeedbackEngine.labelIndex(of: issue.name) {
                            band(for: issue, labelIndex: index, span: span)
                        }
                    }
                }

                HStack {
                    Text("0:00")
                    Spacer()
                    Text(timeLabel(span.end - span.start))
                }
                .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                .foregroundStyle(DS.inkTertiary)
            }
            .padding(.top, 4)
        }
    }

    private func band(for issue: TechniqueIssue, labelIndex: Int,
                      span: (start: Double, end: Double)) -> some View {
        let color = severityColor(issue)
        return HStack(spacing: 10) {
            Text(issue.displayName)
                .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                .foregroundStyle(DS.inkSecondary)
                .lineLimit(1)
                .frame(width: 108, alignment: .leading)

            GeometryReader { geo in
                let total = span.end - span.start
                ZStack(alignment: .leading) {
                    Rectangle().fill(DS.border.opacity(0.5))
                    ForEach(Array(windows.enumerated()), id: \.offset) { _, w in
                        if w.probs.indices.contains(labelIndex) {
                            let x = (w.start - span.start) / total
                            let width = (w.end - w.start) / total
                            Rectangle()
                                .fill(color.opacity(Double(max(0, w.probs[labelIndex] - 0.13)) * 1.1))
                                .frame(width: geo.size.width * width)
                                .offset(x: geo.size.width * x)
                                .onTapGesture { onSelect(w.start) }
                        }
                    }
                }
            }
            .frame(height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(issue.displayName) intensity over time. Double-tap the row's strongest moment via the see-it button in the issue list.")
    }

    private func severityColor(_ issue: TechniqueIssue) -> Color {
        switch issue.severity {
        case .major:    return DS.severityMajor
        case .moderate: return DS.severityModerate
        case .minor:    return DS.severityMinor
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
