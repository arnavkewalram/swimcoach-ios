import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @Query(sort: \SwimSession.analyzedAt, order: .reverse) private var sessions: [SwimSession]
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @State private var sessionToRename: SwimSession? = nil
    @State private var compareSelection: [SwimSession] = []
    @State private var selectingForCompare = false

    private var bestScore: Int { sessions.map(\.score).max() ?? 0 }
    private var avgScore: Int {
        guard !sessions.isEmpty else { return 0 }
        return sessions.map(\.score).reduce(0, +) / sessions.count
    }

    // Chronological order for the chart
    private var chronologicalSessions: [SwimSession] {
        sessions.reversed()
    }

    var body: some View {
        ZStack {
            DS.background.ignoresSafeArea()

            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No sessions yet",
                        systemImage: "figure.pool.swim",
                        description: Text("Analyze a swim to see your history here.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            summaryStrip
                                .padding(.top, 8)

                            if sessions.count >= 2 {
                                ScoreTrendChart(sessions: chronologicalSessions) { session in
                                    if let result = session.decoded() {
                                        router.push(.results(result))
                                    }
                                }
                            }

                            if sessions.count >= 2 {
                                IssueFrequencyChart(sessions: sessions)
                            }

                            SectionHeader(title: "Sessions")
                                .padding(.top, 8)

                            if selectingForCompare {
                                Text("Pick two sessions to compare")
                                    .font(.footnote)
                                    .foregroundStyle(DS.accent)
                            }

                            LazyVStack(spacing: 8) {
                                ForEach(sessions) { session in
                                    Button {
                                        if selectingForCompare {
                                            toggleCompare(session)
                                        } else if let result = session.decoded() {
                                            router.push(.results(result))
                                        }
                                    } label: {
                                        SessionRow(session: session,
                                                   isSelected: compareSelection.contains { $0.id == session.id })
                                    }
                                    .buttonStyle(ScaleButtonStyle())
                                    .contextMenu {
                                        Button {
                                            sessionToRename = session
                                        } label: {
                                            Label("Rename", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                                                SessionVideoStore.delete(
                                                    fileName: sessions[idx].decoded()?.videoFileName)
                                                context.delete(sessions[idx])
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.bottom, 32)
                        }
                        .padding(.horizontal, 24)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .sheet(item: $sessionToRename) { session in
            RenameSessionSheet(session: session)
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DS.background, for: .navigationBar)
        .toolbar {
            if sessions.count >= 2 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selectingForCompare ? "Cancel" : "Compare") {
                        selectingForCompare.toggle()
                        compareSelection = []
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DS.accent)
                }
            }
        }
    }

    private func toggleCompare(_ session: SwimSession) {
        if let idx = compareSelection.firstIndex(where: { $0.id == session.id }) {
            compareSelection.remove(at: idx)
            return
        }
        compareSelection.append(session)
        guard compareSelection.count == 2,
              let a = compareSelection[0].decoded(),
              let b = compareSelection[1].decoded() else { return }
        let (earlier, later) = a.analyzedAt <= b.analyzedAt ? (a, b) : (b, a)
        selectingForCompare = false
        compareSelection = []
        router.push(.compare(earlier: earlier, later: later))
    }

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            summaryCell(value: "\(sessions.count)", label: "SESSIONS")
            summaryDivider
            summaryCell(value: "\(bestScore)", label: "BEST")
            summaryDivider
            summaryCell(value: "\(avgScore)", label: "AVERAGE")
        }
        .padding(.vertical, 14)
        .glassCard()
    }

    private var summaryDivider: some View {
        Rectangle().fill(DS.border).frame(width: 1, height: 34)
    }

    private func summaryCell(value: String, label: String) -> some View {
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

// MARK: - Session row

private struct SessionRow: View {
    let session: SwimSession
    var isSelected: Bool = false

    private var gradeColor: Color { DS.gradeColor(session.grade) }

    var body: some View {
        HStack(spacing: 14) {
            Text(session.grade)
                .font(.grotesk(22, .bold))
                .foregroundStyle(gradeColor)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.name.isEmpty
                     ? session.analyzedAt.formatted(date: .abbreviated, time: .shortened)
                     : session.name)
                    .font(.grotesk(15, .medium))
                    .foregroundStyle(DS.ink)
                Text("Score \(session.score) · \(session.issueCount) issue\(session.issueCount == 1 ? "" : "s") · \(session.strokeCount) strokes")
                    .font(.caption)
                    .foregroundStyle(DS.inkSecondary)
            }

            Spacer()

            Image(systemName: "arrow.right")
                .font(.footnote.weight(.medium))
                .foregroundStyle(DS.inkTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassCard(borderColor: isSelected ? DS.accent : DS.border)
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                .fill(isSelected ? DS.accent : gradeColor)
                .frame(width: 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(session.name.isEmpty ? session.analyzedAt.formatted(date: .abbreviated, time: .shortened) : session.name), " +
            "score \(session.score), grade \(session.grade), \(session.issueCount) issues"
        )
    }
}

// MARK: - Score trend chart

private struct ScoreTrendChart: View {
    let sessions: [SwimSession]
    let onSelect: (SwimSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Score trend")
            Text("Tap a point to open that session")
                .font(.caption)
                .foregroundStyle(DS.inkTertiary)

            Chart {
                ForEach(Array(sessions.enumerated()), id: \.offset) { idx, session in
                    LineMark(
                        x: .value("Session", idx + 1),
                        y: .value("Score", session.score)
                    )
                    .foregroundStyle(DS.accent)

                    PointMark(
                        x: .value("Session", idx + 1),
                        y: .value("Score", session.score)
                    )
                    .foregroundStyle(DS.gradeColor(session.grade))
                    .symbolSize(46)
                }

                let avg = sessions.map(\.score).reduce(0, +) / sessions.count
                RuleMark(y: .value("Average", avg))
                    .foregroundStyle(DS.inkTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .topLeading, alignment: .leading) {
                        Text("AVG \(avg)")
                            .font(.statUnit)
                            .tracking(0.8)
                            .foregroundStyle(DS.inkTertiary)
                    }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine().foregroundStyle(DS.border.opacity(0.6))
                    AxisTick().foregroundStyle(Color.clear)
                    AxisValueLabel()
                        .foregroundStyle(DS.inkTertiary)
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { _ in
                    AxisGridLine().foregroundStyle(DS.border.opacity(0.6))
                    AxisValueLabel()
                        .foregroundStyle(DS.inkTertiary)
                        .font(.caption2)
                }
            }
            .frame(height: 150)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let origin = geo[proxy.plotAreaFrame].origin
                            let x = location.x - origin.x
                            if let idx: Int = proxy.value(atX: x, as: Int.self) {
                                let clampedIdx = max(0, min(idx - 1, sessions.count - 1))
                                onSelect(sessions[clampedIdx])
                            }
                        }
                }
            }
        }
        .padding(16)
        .glassCard()
    }
}

// MARK: - Issue frequency chart

private struct IssueFrequencyChart: View {
    let sessions: [SwimSession]

    private struct IssueFreqItem {
        let name: String
        let count: Int
        var shortName: String {
            name.count > 18 ? String(name.prefix(17)) + "…" : name
        }
    }

    private var topIssues: [IssueFreqItem] {
        var tally: [String: Int] = [:]
        for session in sessions {
            guard let result = session.decoded() else { continue }
            for issue in result.issues {
                tally[issue.displayName, default: 0] += 1
            }
        }
        return tally
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { IssueFreqItem(name: $0.key, count: $0.value) }
    }

    var body: some View {
        let issues = topIssues
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Common issues")

                Chart(issues, id: \.name) { item in
                    BarMark(
                        x: .value("Count", item.count),
                        y: .value("Issue", item.shortName)
                    )
                    .foregroundStyle(DS.accent.opacity(0.85))
                    .cornerRadius(3)
                    .annotation(position: .trailing) {
                        Text("\(item.count)")
                            .font(.grotesk(11, .bold))
                            .foregroundStyle(DS.inkSecondary)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .foregroundStyle(DS.ink)
                            .font(.caption2)
                    }
                }
                .frame(height: CGFloat(issues.count) * 34 + 16)
            }
            .padding(16)
            .glassCard()
        }
    }
}

// MARK: - Rename session sheet

private struct RenameSessionSheet: View {
    let session: SwimSession
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(session: SwimSession) {
        self.session = session
        _name = State(initialValue: session.name)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.background.ignoresSafeArea()

                VStack(spacing: 20) {
                    TextField("Session name", text: $name)
                        .font(.callout)
                        .foregroundStyle(DS.ink)
                        .padding(12)
                        .background(DS.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(DS.borderBold, lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 24)

                    Spacer()
                }
            }
            .navigationTitle("Rename Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(DS.inkSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        session.name = name.trimmingCharacters(in: .whitespaces)
                        dismiss()
                    }
                    .foregroundStyle(DS.accent)
                    .font(.callout.weight(.semibold))
                }
            }
        }
        .presentationDetents([.height(200)])
        .presentationBackground(DS.background)
    }
}
