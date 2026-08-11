import SwiftUI
import SwiftData

// MARK: - First-run welcome card

/// The zero-session state. It used to be a dead end: it described a technique
/// score, detected faults and drills to somebody who could not see any of
/// them without first going to a pool, and there was no other way to find out
/// what the app did.
///
/// The footer fixes that without softening the ask. Filming is still the
/// headline and still the point — the sample swims are offered underneath it,
/// in the quiet register, as the thing to do while you are not at the water.
struct FirstRunCard: View {
    /// Opens the sample swims.
    let onTrySample: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            .accessibilityElement(children: .combine)

            Rectangle().fill(DS.border).frame(height: 1)
                .padding(.top, 4)

            Button(action: onTrySample) {
                HStack(spacing: 5) {
                    Text("OR TRY A SAMPLE SWIM")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                        .tracking(1.2)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(DS.accent)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Try a sample swim")
            .accessibilityHint("Analyzes one of four clips that ship with the app. Nothing is saved to your history.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .padding(.bottom, -6)
        .glassCard()
    }
}

// MARK: - Home index row

/// One line of Home's index: where it goes, the count that justifies going
/// there, and a rule underneath. History, the drill library and the sample
/// swims all sit at this weight — none of them is the move the page is
/// asking for, and none may out-shout "Analyze a swim".
///
/// Extracted when the third one arrived: the two that existed had been
/// copied line for line, and a third copy would have been the point at which
/// they started drifting apart.
///
/// At accessibility text sizes the count drops to its own line instead of
/// fighting the title for one that can no longer hold both.
struct HomeIndexRow: View {
    let title: String
    /// Register text, already in its final casing ("12 SESSIONS", "4 CLIPS").
    let count: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        titleText
                        HStack(spacing: 8) {
                            countText
                            Spacer(minLength: 0)
                            arrow
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        titleText
                        Spacer(minLength: 0)
                        countText
                        arrow
                    }
                }
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(DS.border).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var titleText: some View {
        Text(title)
            .font(.grotesk(15, .medium))
            .foregroundStyle(DS.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var countText: some View {
        Text(count)
            .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
            .tracking(1.2)
            .foregroundStyle(DS.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.caption.weight(.medium))
            .foregroundStyle(DS.inkTertiary)
            .accessibilityHidden(true)
    }
}

// MARK: - Unfinished takes strip

/// The way back to clips the app filmed but never scored.
///
/// Deliberately the quietest actionable thing on the page: a lane-ruled
/// annotation in the data register, no fill and no card, so the one filled
/// button on Home stays "Analyze a swim". It is placed under that hero rather
/// than beside it because recovering a take is a correction, not the main
/// move — but it carries the ochre count stamp the failure screen uses for a
/// swim that did not count, because a lap the user actually filmed going
/// missing is the whole reason this exists.
///
/// Absent entirely at zero takes: the caller does not render it, so there is
/// no empty state to clutter the sheet.
struct UnfinishedTakesStrip: View {
    let takes: [UnfinishedTakes.Take]
    let onOpen: () -> Void

    private var retentionDays: Int {
        Int((UnfinishedTakes.retention / 86_400).rounded())
    }

    private var headline: String {
        takes.count == 1
            ? "1 clip filmed but never analyzed"
            : "\(takes.count) clips filmed but never analyzed"
    }

    private var provenance: String {
        guard let newest = takes.first?.capturedAt else { return "" }
        return "Newest \(newest.formatted(.dateTime.day().month(.abbreviated))) · kept \(retentionDays) days"
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("UNFINISHED TAKES")
                        .font(.sectionLabel)
                        .tracking(1.6)
                        .foregroundStyle(DS.inkSecondary)
                        .fixedSize()
                    LaneRule()
                    Text("\(takes.count)")
                        .font(.grotesk(12, .bold))
                        .foregroundStyle(DS.severityModerate)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 4)
                            .stroke(DS.severityModerate.opacity(0.55), lineWidth: 1))
                }

                Text(headline)
                    .font(.grotesk(15, .medium))
                    .foregroundStyle(DS.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(provenance)
                    .font(.caption)
                    .foregroundStyle(DS.inkTertiary)

                HStack(spacing: 5) {
                    Text("RECOVER THEM")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                        .tracking(1.2)
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(DS.accent)
                .padding(.top, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(headline). \(provenance). Opens unfinished takes.")
        // The label carries a live date, so route tests address the strip by
        // identifier rather than pinning today's copy.
        .accessibilityIdentifier("unfinishedTakesStrip")
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
