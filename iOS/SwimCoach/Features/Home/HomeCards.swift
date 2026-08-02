import SwiftUI
import SwiftData

// MARK: - First-run welcome card

struct FirstRunCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FIRST SESSION")
                .font(.sectionLabel)
                .tracking(1.6)
                .foregroundStyle(DS.accent)
            Text("Film your first swim")
                .font(.grotesk(22, .bold))
                .foregroundStyle(DS.ink)
            Text("Record a side-on video from the pool deck, 3–6 m from the swimmer. You'll get a technique score, detected faults, and drills in under a minute.")
                .font(.footnote)
                .lineSpacing(3)
                .foregroundStyle(DS.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Record strip (session count · best · average)

struct RecordStrip: View {
    let sessions: [SwimSession]

    private var bestScore: Int { sessions.map(\.score).max() ?? 0 }
    private var avgScore: Int {
        guard !sessions.isEmpty else { return 0 }
        return sessions.map(\.score).reduce(0, +) / sessions.count
    }

    var body: some View {
        HStack(spacing: 0) {
            cell(value: "\(sessions.count)", label: "SESSIONS")
            divider
            cell(value: "\(bestScore)", label: "BEST")
            divider
            cell(value: "\(avgScore)", label: "AVERAGE")
        }
        .padding(.vertical, 4)
    }

    private var divider: some View {
        Rectangle().fill(DS.border).frame(width: 1, height: 34)
    }

    private func cell(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.grotesk(22, .bold))
                .foregroundStyle(DS.ink)
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
}

// MARK: - Last Session Card

struct LastSessionCard: View {
    let session: SwimSession
    let previousSession: SwimSession?
    let onTap: () -> Void

    private var gradeColor: Color { DS.gradeColor(session.grade) }

    private var delta: Int? {
        guard let prev = previousSession else { return nil }
        return session.score - prev.score
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("LAST SESSION")
                        .font(.sectionLabel)
                        .tracking(1.6)
                        .foregroundStyle(DS.inkTertiary)
                    Spacer()
                    Text(session.analyzedAt.formatted(date: .abbreviated, time: .omitted).uppercased())
                        .font(.sectionLabel)
                        .tracking(0.8)
                        .foregroundStyle(DS.inkTertiary)
                }
                .padding(.bottom, 18)

                HStack(spacing: 22) {
                    ZStack {
                        ScoreArc(score: session.score, color: gradeColor)
                            .frame(width: 116, height: 116)
                        VStack(spacing: 0) {
                            Text("\(session.score)")
                                .font(.grotesk(38, .bold))
                                .foregroundStyle(DS.ink)
                            Text(session.grade)
                                .font(.grotesk(15, .bold))
                                .foregroundStyle(gradeColor)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        if let d = delta, d != 0 {
                            HStack(spacing: 5) {
                                Image(systemName: d > 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.caption2.weight(.semibold))
                                    .accessibilityHidden(true)
                                Text(d > 0 ? "UP \(d) PTS" : "DOWN \(-d) PTS")
                                    .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                                    .tracking(1.2)
                            }
                            .foregroundStyle(d > 0 ? DS.severityMinor : DS.severityModerate)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(session.issueCount) issue\(session.issueCount == 1 ? "" : "s")")
                                .font(.grotesk(15, .medium))
                                .foregroundStyle(DS.ink)
                            Text("\(session.strokeCount) strokes")
                                .font(.footnote)
                                .foregroundStyle(DS.inkSecondary)
                        }
                        HStack(spacing: 5) {
                            Text("FULL RESULTS")
                                .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                                .tracking(1.2)
                            Image(systemName: "arrow.right")
                                .font(.caption2.weight(.semibold))
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(DS.accent)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 14)
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Last session: score \(session.score), grade \(session.grade), " +
            "\(session.issueCount) issue\(session.issueCount == 1 ? "" : "s"). Opens full results."
        )
    }
}
