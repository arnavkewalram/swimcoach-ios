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
    @State private var searchQuery = ""
    @State private var gradeFilter: Set<String> = []
    @State private var swimmerFilter: Set<String> = []

    /// Charts and stats follow the swimmer filter (an identity scope) but
    /// deliberately ignore grade/search — those only narrow the list.
    private var swimmerScopedSessions: [SwimSession] {
        swimmerFilter.isEmpty
            ? Array(sessions)
            : sessions.filter { swimmerFilter.contains($0.swimmer) }
    }

    private var bestScore: Int { swimmerScopedSessions.map(\.score).max() ?? 0 }
    private var avgScore: Int {
        guard !swimmerScopedSessions.isEmpty else { return 0 }
        return swimmerScopedSessions.map(\.score).reduce(0, +) / swimmerScopedSessions.count
    }

    // Chronological order for the chart
    private var chronologicalSessions: [SwimSession] {
        swimmerScopedSessions.reversed()
    }

    private var filteredSessions: [SwimSession] {
        sessions.filter { session in
            SessionFilter.matches(grades: gradeFilter, grade: session.grade)
            && SessionFilter.matches(swimmers: swimmerFilter, swimmer: session.swimmer)
            && SessionFilter.matches(
                query: searchQuery,
                name: session.name,
                notes: session.notes,
                dateText: session.analyzedAt.formatted(date: .abbreviated, time: .shortened),
                swimmer: session.swimmer)
        }
    }

    private var presentSwimmers: [String] {
        Array(Set(sessions.map(\.swimmer).filter { !$0.isEmpty })).sorted()
    }

    private var presentGrades: [String] {
        let order = ["A", "B", "C", "D", "F"]
        let present = Set(sessions.map(\.grade))
        return order.filter { present.contains($0) }
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
                            if presentSwimmers.count > 1 {
                                swimmerChips
                                    .padding(.top, 8)
                            }

                            summaryStrip
                                .padding(.top, presentSwimmers.count > 1 ? 0 : 8)

                            if swimmerScopedSessions.count >= 2 {
                                ConsistencyStrip(sessions: swimmerScopedSessions)
                            }

                            if swimmerScopedSessions.count >= 2 {
                                ScoreTrendChart(sessions: chronologicalSessions) { session in
                                    if let result = session.decoded() {
                                        router.push(.results(result))
                                    }
                                }
                            }

                            if swimmerScopedSessions.count >= 2 {
                                IssueFrequencyChart(sessions: swimmerScopedSessions)
                            }

                            SectionHeader(title: "Sessions")
                                .padding(.top, 8)

                            if presentGrades.count > 1 {
                                gradeChips
                            }

                            if selectingForCompare {
                                Text("Pick two sessions to compare")
                                    .font(.footnote)
                                    .foregroundStyle(DS.accent)
                            }

                            if filteredSessions.isEmpty {
                                Text("No sessions match")
                                    .font(.footnote)
                                    .foregroundStyle(DS.inkTertiary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                            }

                            LazyVStack(spacing: 8) {
                                ForEach(filteredSessions) { session in
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
                                            Label("Edit name & notes", systemImage: "pencil")
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
        .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Name, notes, or date")
        .sheet(item: $sessionToRename) { session in
            EditSessionSheet(session: session)
        }
        #if DEBUG
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-historySwimmer"), i + 1 < args.count {
                swimmerFilter = [args[i + 1]]
            }
        }
        #endif
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("History")
                    .font(.grotesk(17, .medium))
                    .foregroundStyle(DS.ink)
            }
        }
        .toolbarBackground(DS.background, for: .navigationBar)
        .toolbar {
            if sessions.count >= 2 {
                ToolbarItem(placement: .topBarTrailing) {
                    // Micro-label action, matching FULL RESULTS / COMPARE TO
                    // PREVIOUS SESSION — not the system title-case button.
                    Button {
                        selectingForCompare.toggle()
                        compareSelection = []
                    } label: {
                        Text(selectingForCompare ? "CANCEL" : "COMPARE")
                            .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                            .tracking(1.2)
                            .foregroundStyle(DS.accent)
                            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(selectingForCompare
                                        ? "Cancel comparing"
                                        : "Compare two sessions")
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

    /// Swimmer scope row — same capsule language as Home's swimmer scope.
    /// EVERYONE is selected whenever no swimmer filter is active (empty
    /// selection = everyone, per `SessionFilter.matches`).
    private var swimmerChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                swimmerChip(label: "Everyone",
                            isOn: swimmerFilter.isEmpty,
                            accessibilityLabel: "Show everyone's sessions") {
                    swimmerFilter = []
                }
                ForEach(presentSwimmers, id: \.self) { swimmer in
                    let isOn = swimmerFilter.contains(swimmer)
                    swimmerChip(label: swimmer,
                                isOn: isOn,
                                accessibilityLabel: "\(isOn ? "Remove" : "Add") \(swimmer) filter") {
                        swimmerFilter = SessionFilter.toggling(swimmerFilter, swimmer: swimmer)
                    }
                }
            }
        }
    }

    /// Capsule chip matching HomeView's `swimmerScopeChip` styling.
    private func swimmerChip(label: String, isOn: Bool,
                             accessibilityLabel: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                .tracking(1.0)
                .foregroundStyle(isOn ? .white : DS.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isOn ? DS.accent : .clear)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(
                    DS.accent.opacity(isOn ? 0 : 0.5), lineWidth: 1))
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var gradeChips: some View {
        HStack(spacing: 8) {
            ForEach(presentGrades, id: \.self) { grade in
                let isOn = gradeFilter.contains(grade)
                Button {
                    if isOn { gradeFilter.remove(grade) } else { gradeFilter.insert(grade) }
                } label: {
                    Text(grade)
                        .font(.grotesk(13, .bold))
                        .foregroundStyle(isOn ? .white : DS.gradeColor(grade))
                        .frame(width: 34, height: 30)
                        .background(isOn ? DS.gradeColor(grade) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7)
                            .stroke(DS.gradeColor(grade).opacity(isOn ? 0 : 0.5), lineWidth: 1))
                }
                .accessibilityLabel("\(isOn ? "Remove" : "Add") grade \(grade) filter")
            }
            if !gradeFilter.isEmpty {
                Button("Clear") { gradeFilter = [] }
                    .font(.footnote)
                    .foregroundStyle(DS.accent)
            }
            Spacer()
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            summaryCell(value: "\(swimmerScopedSessions.count)", label: "SESSIONS")
            summaryDivider
            summaryCell(value: "\(bestScore)", label: "BEST")
            summaryDivider
            summaryCell(value: "\(avgScore)", label: "AVERAGE")
        }
        .padding(.vertical, 6)
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

// MARK: - Consistency strip (sessions per week, trailing 12)

private struct ConsistencyStrip: View {
    let sessions: [SwimSession]

    private var counts: [Int] {
        TrainingLog.weeklyCounts(
            for: sessions.map { TrainingLog.Entry(date: $0.analyzedAt, score: $0.score) })
    }

    private var streak: Int {
        TrainingLog.weeklyStreak(
            for: sessions.map { TrainingLog.Entry(date: $0.analyzedAt, score: $0.score) })
    }

    var body: some View {
        let counts = counts
        let peak = max(counts.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("CONSISTENCY")
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                    .tracking(1.4)
                    .foregroundStyle(DS.inkTertiary)
                if streak >= 2 {
                    Text("\(streak)-WEEK STREAK")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                        .tracking(1.2)
                        .foregroundStyle(DS.severityMinor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 4)
                            .stroke(DS.severityMinor.opacity(0.55), lineWidth: 1))
                }
                Spacer()
                Text("SESSIONS / WEEK · LAST 12")
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                    .tracking(1.0)
                    .foregroundStyle(DS.inkTertiary)
            }
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(counts.enumerated()), id: \.offset) { _, count in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(count > 0 ? DS.accent : DS.border)
                        .frame(height: count > 0
                               ? max(8, CGFloat(count) / CGFloat(peak) * 34)
                               : 3)
                        .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 36, alignment: .bottom)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(consistencyAccessibilityLabel)
    }

    private var consistencyAccessibilityLabel: String {
        let active = counts.filter { $0 > 0 }.count
        var label = "Consistency: sessions in \(active) of the last 12 weeks."
        if streak >= 2 { label += " \(streak) week streak." }
        return label
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
                if !session.swimmer.isEmpty || !session.notes.isEmpty {
                    HStack(spacing: 6) {
                        if !session.swimmer.isEmpty {
                            Text(session.swimmer.uppercased())
                                .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                                .tracking(1.0)
                                .foregroundStyle(DS.accent)
                        }
                        if !session.notes.isEmpty {
                            Text(session.notes)
                                .font(.caption.italic())
                                .foregroundStyle(DS.inkTertiary)
                                .lineLimit(1)
                        }
                    }
                }
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

    private var averageScore: Int {
        sessions.isEmpty ? 0 : sessions.map(\.score).reduce(0, +) / sessions.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Score trend")
            Text("Tap a point to open that session · dashed line = average \(averageScore)")
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

                RuleMark(y: .value("Average", averageScore))
                    .foregroundStyle(DS.inkTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartYScale(domain: 0...100)
            // Pin the domain to real session indices — .automatic invents
            // negative "sessions" when the plot gets narrow (large type).
            .chartXScale(domain: 0.5...(Double(sessions.count) + 0.5))
            .chartXAxis {
                AxisMarks(values: Array(stride(
                    from: 1, through: sessions.count,
                    by: max(1, sessions.count / 5)))) { _ in
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
                            guard let plotFrame = proxy.plotFrame else { return }
                            let origin = geo[plotFrame].origin
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
        let trend: IssueTrend
    }

    private var topIssues: [IssueFreqItem] {
        // One decode pass: chronological presence flags per fault
        let decoded = sessions.reversed().compactMap { $0.decoded() }   // oldest first
        var presence: [String: [Bool]] = [:]
        for result in decoded {
            let names = Set(result.issues.map(\.displayName))
            let priorCount = presence.values.first?.count ?? 0
            for name in Set(presence.keys).union(names) {
                presence[name, default: [Bool](repeating: false, count: priorCount)]
                    .append(names.contains(name))
            }
        }
        // Backfill: faults first seen mid-history need leading falses
        let total = decoded.count
        for (name, flags) in presence where flags.count < total {
            presence[name] = [Bool](repeating: false, count: total - flags.count) + flags
        }
        return presence
            .map { (name: $0.key, flags: $0.value) }
            .map { IssueFreqItem(name: $0.name,
                                 count: $0.flags.filter { $0 }.count,
                                 trend: IssueTrend.trend(occurrences: $0.flags)) }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        let issues = topIssues
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Common issues")
                if sessions.count >= IssueTrend.minSessions {
                    Text("Arrows compare your recent sessions to earlier ones")
                        .font(.caption)
                        .foregroundStyle(DS.inkTertiary)
                }

                Chart(issues, id: \.name) { item in
                    BarMark(
                        x: .value("Count", item.count),
                        y: .value("Issue", item.name)
                    )
                    .foregroundStyle(DS.accent.opacity(0.85))
                    .cornerRadius(3)
                    .annotation(position: .trailing) {
                        HStack(spacing: 4) {
                            Text("\(item.count)")
                                .font(.grotesk(11, .bold))
                                .foregroundStyle(DS.inkSecondary)
                            if item.trend != .flat {
                                Image(systemName: item.trend == .improving
                                      ? "arrow.down.right" : "arrow.up.right")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(item.trend == .improving
                                                     ? DS.severityMinor : DS.severityMajor)
                                    .accessibilityLabel(item.trend == .improving
                                                        ? "improving" : "worsening")
                            }
                        }
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { value in
                        // Full fault names, wrapped to two lines in a capped
                        // label column — no manual "…" truncation.
                        AxisValueLabel {
                            Text(value.as(String.self) ?? "")
                                .font(.caption2)
                                .foregroundStyle(DS.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 96, alignment: .trailing)
                        }
                    }
                }
                .frame(height: CGFloat(issues.count) * 34 + 16)
            }
            .padding(16)
            .glassCard()
        }
    }
}

// MARK: - Edit session sheet (name + notes)

struct EditSessionSheet: View {
    let session: SwimSession
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var notes: String
    @State private var swimmer: String

    init(session: SwimSession) {
        self.session = session
        _name = State(initialValue: session.name)
        _notes = State(initialValue: session.notes)
        _swimmer = State(initialValue: session.swimmer)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
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

                    VStack(alignment: .leading, spacing: 6) {
                        Text("SWIMMER")
                            .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                            .tracking(1.2)
                            .foregroundStyle(DS.inkTertiary)
                        TextField("Who swam? (optional)", text: $swimmer)
                            .font(.callout)
                            .foregroundStyle(DS.ink)
                            .padding(12)
                            .background(DS.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(DS.borderBold, lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOTES")
                            .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                            .tracking(1.2)
                            .foregroundStyle(DS.inkTertiary)
                        TextField("How did it feel? What did you work on?",
                                  text: $notes, axis: .vertical)
                            .font(.callout)
                            .foregroundStyle(DS.ink)
                            .lineLimit(3...6)
                            .padding(12)
                            .background(DS.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(DS.borderBold, lineWidth: 1)
                            )
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .navigationTitle("Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Edit Session")
                        .font(.grotesk(17, .medium))
                        .foregroundStyle(DS.ink)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(DS.inkSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        session.name = name.trimmingCharacters(in: .whitespaces)
                        session.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        session.swimmer = swimmer.trimmingCharacters(in: .whitespaces)
                        dismiss()
                    }
                    .foregroundStyle(DS.accent)
                    .font(.callout.weight(.semibold))
                }
            }
        }
        .presentationDetents([.height(430)])
        .presentationBackground(DS.background)
    }
}
