import SwiftUI
import SwiftData

// MARK: - Focus fault panel

struct FocusPanel: View {
    let faultName: String
    let occurrences: Int
    let windowSize: Int
    let onDrills: () -> Void

    private var info: (display: String, severity: TechniqueIssue.Severity)? {
        FeedbackEngine.displayInfo(for: faultName)
    }

    private var severityColor: Color {
        switch info?.severity {
        case .major: return DS.severityMajor
        case .moderate: return DS.severityModerate
        default: return DS.severityMinor
        }
    }

    var body: some View {
        Button(action: onDrills) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Focus")
                HStack(alignment: .firstTextBaseline) {
                    Rectangle()
                        .fill(severityColor)
                        .frame(width: 3, height: 20)
                        .offset(y: 2)
                    Text(info?.display ?? faultName)
                        .font(.grotesk(20, .bold))
                        .foregroundStyle(DS.ink)
                    Spacer()
                }
                Text("In \(occurrences) of your last \(windowSize) session\(windowSize == 1 ? "" : "s")")
                    .font(.footnote)
                    .foregroundStyle(DS.inkSecondary)
                HStack(spacing: 5) {
                    Text("DRILLS FOR THIS")
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
        .accessibilityLabel(
            "Focus: \(info?.display ?? faultName), in \(occurrences) of your last \(windowSize) sessions. Opens drills.")
    }
}


// MARK: - Training log (sparkline + this-week line)

struct TrainingLogPanel: View {
    let sessions: [SwimSession]
    @AppStorage("activeSwimmer") private var activeSwimmer: String = ""
    @State private var showGoalSheet = false

    /// Goal for the active swimmer (falls back to the Everyone goal).
    /// Recomputed on swimmer switches and on goal-sheet dismissal — the
    /// sheet is the only writer, so those cover every change.
    private var weeklyGoal: Int {
        WeeklyGoalStore().goal(for: activeSwimmer)
    }

    private var entries: [TrainingLog.Entry] {
        sessions.map { TrainingLog.Entry(date: $0.analyzedAt, score: $0.score) }
    }

    private var thisWeek: TrainingLog.WeekSummary {
        TrainingLog.summary(for: entries, weekContaining: Date())
    }

    private var delta: Int? {
        TrainingLog.weekOverWeekDelta(for: entries)
    }

    private var streak: Int {
        TrainingLog.weeklyStreak(for: entries)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                SectionHeader(title: "Training log")
                if streak >= 2 {
                    Text("\(streak)-WEEK STREAK")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                        .tracking(1.2)
                        .foregroundStyle(DS.severityMinor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 4)
                            .stroke(DS.severityMinor.opacity(0.55), lineWidth: 1))
                        .fixedSize()
                }
            }

            Sparkline(values: TrainingLog.recentScores(from: entries))
                .frame(height: 46)

            HStack(alignment: .firstTextBaseline) {
                Text("THIS WEEK")
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                    .tracking(1.2)
                    .foregroundStyle(DS.inkTertiary)
                Text(thisWeek.sessionCount == 0
                     ? "No sessions yet"
                     : "\(thisWeek.sessionCount) session\(thisWeek.sessionCount == 1 ? "" : "s") · avg \(thisWeek.averageScore)")
                    .font(.grotesk(14, .medium))
                    .foregroundStyle(DS.ink)
                Spacer()
                if let d = delta, d != 0 {
                    HStack(spacing: 4) {
                        Image(systemName: d > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2.weight(.semibold))
                            .accessibilityHidden(true)
                        Text("\(abs(d)) VS LAST WK")
                            .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                            .tracking(1.2)
                    }
                    .foregroundStyle(d > 0 ? DS.severityMinor : DS.severityModerate)
                }
            }

            goalRow
        }
        .sheet(isPresented: $showGoalSheet) {
            WeeklyGoalSheet()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trainingLogAccessibilityLabel)
    }

    @ViewBuilder
    private var goalRow: some View {
        Button {
            showGoalSheet = true
        } label: {
            HStack(spacing: 10) {
                if let ticks = TrainingLog.goalTicks(
                    sessionCount: thisWeek.sessionCount, goal: weeklyGoal) {
                    HStack(spacing: 4) {
                        ForEach(0..<ticks.total, id: \.self) { i in
                            Rectangle()
                                .fill(i < ticks.filled ? DS.accent : Color.clear)
                                .frame(width: 14, height: 6)
                                .overlay(Rectangle().stroke(
                                    i < ticks.filled ? DS.accent : DS.borderBold, lineWidth: 1))
                        }
                        if ticks.overflow > 0 {
                            Text("+\(ticks.overflow)")
                                .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                                .tracking(0.8)
                                .foregroundStyle(DS.accent)
                        }
                    }
                    Text("\(ticks.filled) OF \(ticks.total) GOAL")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                        .tracking(1.2)
                        .foregroundStyle(DS.inkTertiary)
                    Spacer()
                    if ticks.isMet {
                        Text("GOAL MET")
                            .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                            .tracking(1.2)
                            .foregroundStyle(DS.severityMinor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .stroke(DS.severityMinor.opacity(0.55), lineWidth: 1))
                    }
                } else {
                    Text("SET A WEEKLY GOAL")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                        .tracking(1.2)
                        .foregroundStyle(DS.accent)
                    Spacer()
                    Image(systemName: "plus")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DS.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.top, 2)
            // Row content is short; the frame extends the tap target to
            // the HIG 44pt minimum without changing the visual weight.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(goalAccessibilityLabel)
        .accessibilityHint("Opens the weekly goal setting")
    }

    private var goalAccessibilityLabel: String {
        guard let ticks = TrainingLog.goalTicks(
            sessionCount: thisWeek.sessionCount, goal: weeklyGoal) else {
            return "Set a weekly session goal"
        }
        var label = "Weekly goal: \(ticks.filled) of \(ticks.total) sessions"
        if ticks.isMet { label += ". Goal met" }
        return label
    }

    private var trainingLogAccessibilityLabel: String {
        var label = thisWeek.sessionCount == 0
            ? "Training log. No sessions yet this week."
            : "Training log. \(thisWeek.sessionCount) session\(thisWeek.sessionCount == 1 ? "" : "s") this week, average score \(thisWeek.averageScore)."
        if let d = delta, d != 0 {
            label += d > 0
                ? " Up \(d) points versus last week."
                : " Down \(-d) points versus last week."
        }
        return label
    }
}

