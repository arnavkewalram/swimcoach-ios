import SwiftUI

// MARK: - Issue row

struct IssueRow: View {
    let issue: TechniqueIssue
    var canSeek: Bool = false
    var onSeeIt: () -> Void = {}
    var onDrills: () -> Void = {}
    @State private var expanded = false

    private var severityColor: Color {
        switch issue.severity {
        case .major:    return DS.severityMajor
        case .moderate: return DS.severityModerate
        case .minor:    return DS.severityMinor
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Text(issue.displayName)
                        .font(.grotesk(15, .medium))
                        .foregroundStyle(DS.ink)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    SeverityBadge(severity: issue.severity.rawValue)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(DS.inkTertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(issue.displayName), \(issue.severity.rawValue) severity")
            .accessibilityHint(expanded ? "Collapses detail" : "Shows detail and drill tip")

            if expanded {
                Rectangle().fill(DS.border).frame(height: 1)
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 12) {
                    Text(issue.description)
                        .font(.footnote)
                        .lineSpacing(3)
                        .foregroundStyle(DS.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .top, spacing: 10) {
                        Text("DRILL")
                            .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                            .tracking(1.2)
                            .foregroundStyle(DS.accent)
                            .padding(.top, 2)
                        Text(issue.tip)
                            .font(.footnote.weight(.medium))
                            .lineSpacing(3)
                            .foregroundStyle(DS.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        if canSeek {
                            Button(action: onSeeIt) {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.circle")
                                        .font(.footnote)
                                        .accessibilityHidden(true)
                                    Text("SEE IT IN YOUR VIDEO")
                                        .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                                        .tracking(1.2)
                                }
                                .foregroundStyle(DS.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(DS.accent.opacity(0.45), lineWidth: 1))
                            }
                            .accessibilityLabel("Play the video where \(issue.displayName) was strongest")
                        }

                        if !DrillCatalog.drills(fixing: issue.name).isEmpty {
                            Button(action: onDrills) {
                                HStack(spacing: 6) {
                                    Image(systemName: "figure.pool.swim")
                                        .font(.footnote)
                                        .accessibilityHidden(true)
                                    Text("DRILLS")
                                        .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                                        .tracking(1.2)
                                }
                                .foregroundStyle(DS.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(DS.accent.opacity(0.45), lineWidth: 1))
                            }
                            .accessibilityLabel("Open drills that fix \(issue.displayName)")
                        }
                    }
                }
                .padding(16)
                .transition(.opacity)
            }
        }
        .glassCard()
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                .fill(severityColor)
                .frame(width: 3)
        }
    }
}

// MARK: - Tip row

struct TipRow: View {
    let index: Int
    let text: String
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Text(String(format: "%02d", index))
                    .font(.grotesk(15, .bold))
                    .foregroundStyle(DS.accent)
                    .padding(.top, 1)
                Text(text)
                    .font(.footnote)
                    .lineSpacing(3)
                    .foregroundStyle(DS.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(16)
            if !isLast {
                Rectangle().fill(DS.border).frame(height: 1)
                    .padding(.leading, 16)
            }
        }
    }
}
