import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @Query(sort: \SwimSession.analyzedAt, order: .reverse) private var sessions: [SwimSession]
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @State private var sessionToRename: SwimSession? = nil

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
                        VStack(spacing: 16) {
                            // Stats summary card
                            HStack(spacing: 0) {
                                HistoryStat(value: "\(sessions.count)", label: "sessions", icon: "list.bullet")
                                Divider().frame(height: 32).background(DS.border)
                                HistoryStat(value: "\(bestScore)", label: "best", icon: "star.fill")
                                Divider().frame(height: 32).background(DS.border)
                                HistoryStat(value: "\(avgScore)", label: "average", icon: "chart.bar.fill")
                            }
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .background(DS.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(DS.border, lineWidth: 1)
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                            // Score trend chart (shown when 2+ sessions)
                            if sessions.count >= 2 {
                                ScoreTrendChart(sessions: chronologicalSessions) { session in
                                    if let result = session.decoded() {
                                        router.push(.results(result))
                                    }
                                }
                                .padding(.horizontal, 16)
                            }

                            // Issue frequency chart (shown when 2+ sessions)
                            if sessions.count >= 2 {
                                IssueFrequencyChart(sessions: sessions)
                                    .padding(.horizontal, 16)
                            }

                            // Session rows
                            LazyVStack(spacing: 10) {
                                ForEach(sessions) { session in
                                    Button {
                                        if let result = session.decoded() {
                                            router.push(.results(result))
                                        }
                                    } label: {
                                        SessionRow(session: session)
                                    }
                                    .buttonStyle(ScaleButtonStyle())
                                    .padding(.horizontal, 16)
                                    .contextMenu {
                                        Button {
                                            sessionToRename = session
                                        } label: {
                                            Label("Rename", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
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
    }
}

// MARK: - History stat cell

private struct HistoryStat: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(DS.accent.opacity(0.7))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Session row

private struct SessionRow: View {
    let session: SwimSession

    private var gradeColor: Color { DS.gradeColor(session.grade) }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                // Grade badge
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [gradeColor.opacity(0.3), gradeColor.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 46)
                    Text(session.grade)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(gradeColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if !session.name.isEmpty {
                        Text(session.name)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(session.analyzedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(session.analyzedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }

                    HStack(spacing: 8) {
                        Text("Score: \(session.score)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Issue dots
                        IssueDots(count: session.issueCount)

                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary.opacity(0.5))

                        Text("\(session.strokeCount) strokes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Score progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [gradeColor, gradeColor.opacity(0.5)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geo.size.width * CGFloat(session.score) / 100,
                            height: 3
                        )
                }
            }
            .frame(height: 3)
        }
        .padding(14)
        .background(DS.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DS.border, lineWidth: 1)
        )
    }
}

// MARK: - Score trend chart

private struct ScoreTrendChart: View {
    let sessions: [SwimSession]
    let onSelect: (SwimSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Score Trend", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Tap a point to view session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(Array(sessions.enumerated()), id: \.offset) { idx, session in
                    LineMark(
                        x: .value("Session", idx + 1),
                        y: .value("Score", session.score)
                    )
                    .foregroundStyle(DS.accent)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Session", idx + 1),
                        yStart: .value("Base", 0),
                        yEnd: .value("Score", session.score)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [DS.accent.opacity(0.3), DS.accent.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Session", idx + 1),
                        y: .value("Score", session.score)
                    )
                    .foregroundStyle(DS.gradeColor(session.grade))
                    .symbolSize(40)
                }

                // Average reference line
                let avg = sessions.map(\.score).reduce(0, +) / sessions.count
                RuleMark(y: .value("Average", avg))
                    .foregroundStyle(Color.white.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .trailing) {
                        Text("avg")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                    AxisTick().foregroundStyle(Color.clear)
                    AxisValueLabel()
                        .foregroundStyle(Color.secondary)
                        .font(.system(size: 10))
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel()
                        .foregroundStyle(Color.secondary)
                        .font(.system(size: 10))
                }
            }
            .frame(height: 140)
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
        .padding(14)
        .background(DS.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DS.border, lineWidth: 1)
        )
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
        if issues.isEmpty { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "COMMON ISSUES", icon: "chart.bar.xaxis")

                Chart(issues, id: \.name) { item in
                    BarMark(
                        x: .value("Count", item.count),
                        y: .value("Issue", item.shortName)
                    )
                    .foregroundStyle(DS.accent.opacity(0.8))
                    .cornerRadius(4)
                    .annotation(position: .trailing) {
                        Text("\(item.count)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .foregroundStyle(Color.white.opacity(0.7))
                            .font(.system(size: 11))
                    }
                }
                .frame(height: CGFloat(issues.count) * 34 + 16)
            }
            .padding(14)
            .background(DS.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(DS.border, lineWidth: 1)
            )
        )
    }
}

// MARK: - Issue dots

private struct IssueDots: View {
    let count: Int

    private var dots: [(Color, String)] {
        // For display: up to 3 colored dots then "+N"
        // We don't have severity per session, so use a neutral orange for all
        let visible = min(count, 3)
        return (0..<visible).map { _ in (.orange, "") }
    }

    var body: some View {
        if count == 0 {
            EmptyView()
        } else {
            HStack(spacing: 3) {
                ForEach(0..<min(count, 3), id: \.self) { _ in
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                }
                if count > 3 {
                    Text("+\(count - 3)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
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
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(DS.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(DS.border, lineWidth: 1)
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
                    .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        session.name = name.trimmingCharacters(in: .whitespaces)
                        dismiss()
                    }
                    .foregroundStyle(DS.accent)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
            }
        }
        .presentationDetents([.height(200)])
        .presentationBackground(DS.background)
    }
}
