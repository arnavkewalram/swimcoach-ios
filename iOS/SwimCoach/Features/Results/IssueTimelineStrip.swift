import SwiftUI

/// Compact severity-colored issue timeline directly under the Results
/// video: one lane spanning the clip duration, with segments where
/// technique issues flared. Tapping a segment seeks the player to that
/// stretch's start. All geometry lives in `IssueTimelineModel`; the strip
/// hides itself entirely for legacy sessions (nil windows) or when the
/// clip duration is unknown.
struct IssueTimelineStrip: View {
    let windows: [IssueWindow]?
    let issues: [TechniqueIssue]
    let durationSeconds: Double?
    let onSeek: (Double) -> Void

    private static let barHeight: CGFloat = 14
    private static let cornerRadius: CGFloat = 3

    var body: some View {
        if let model = IssueTimelineModel.make(windows: windows,
                                               issues: issues,
                                               durationSeconds: durationSeconds) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("ISSUE TIMELINE")
                        .font(.sectionLabel)
                        .tracking(1.6)
                        .foregroundStyle(DS.inkTertiary)
                    Spacer()
                    Text("TAP A MARK TO REVIEW")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                        .tracking(1.2)
                        .foregroundStyle(DS.accent)
                        .accessibilityHidden(true)
                }

                bar(model)

                HStack {
                    Text("0:00")
                    Spacer()
                    Text(timeLabel(model.durationSeconds))
                }
                .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                .foregroundStyle(DS.inkTertiary)
                .accessibilityHidden(true)

                legend(model)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Bar

    private func bar(_ model: IssueTimelineModel) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(DS.surface2)
                ForEach(Array(model.segments.enumerated()), id: \.offset) { _, segment in
                    Rectangle()
                        .fill(severityColor(segment.severity))
                        .frame(width: max(2, geo.size.width * segment.widthFraction))
                        .offset(x: geo.size.width * segment.startFraction)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard geo.size.width > 0 else { return }
                if let time = model.seekTime(atFraction: location.x / geo.size.width) {
                    onSeek(time)
                }
            }
        }
        .frame(height: Self.barHeight)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius)
            .stroke(DS.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(model))
        .accessibilityHint("Use the see-it button on an issue below to jump the video there.")
    }

    // MARK: - Legend

    private func legend(_ model: IssueTimelineModel) -> some View {
        HStack(spacing: 14) {
            ForEach(model.legendSeverities, id: \.self) { severity in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(severityColor(severity))
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(severity.rawValue.uppercased())
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                        .tracking(1.2)
                        .foregroundStyle(DS.inkTertiary)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private func severityColor(_ severity: TechniqueIssue.Severity) -> Color {
        switch severity {
        case .major:    return DS.severityMajor
        case .moderate: return DS.severityModerate
        case .minor:    return DS.severityMinor
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func accessibilitySummary(_ model: IssueTimelineModel) -> String {
        let counts = model.legendSeverities.map { severity in
            let n = model.segments.filter { $0.severity == severity }.count
            return "\(n) \(severity.rawValue)"
        }
        return "Issue timeline: \(counts.joined(separator: ", "))"
            + " marked stretch\(model.segments.count == 1 ? "" : "es")"
            + " across the \(timeLabel(model.durationSeconds)) clip."
    }
}
