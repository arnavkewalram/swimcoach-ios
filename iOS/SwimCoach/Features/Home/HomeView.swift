import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SwimSession.analyzedAt, order: .reverse) private var sessions: [SwimSession]
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    #if DEBUG
    @State private var showFilePicker = false
    @State private var docsVideoURL: URL? = nil
    #endif

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 12 { return "Good morning" }
        if h < 17 { return "Good afternoon" }
        return "Good evening"
    }

    var body: some View {
        ZStack {
            DS.background.ignoresSafeArea()

            GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Masthead ──────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(greeting.uppercased())
                                .font(.sectionLabel)
                                .tracking(2.0)
                                .foregroundStyle(DS.accent)
                            Spacer()
                            Text(Date().formatted(.dateTime.weekday(.wide).day().month()).uppercased())
                                .font(.sectionLabel)
                                .tracking(1.2)
                                .foregroundStyle(DS.inkTertiary)
                        }
                        Text("SwimCoach")
                            .font(.grotesk(40, .bold))
                            .foregroundStyle(DS.ink)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 18)

                    LaneRule()
                        .padding(.bottom, 22)

                    // ── Last session / first run ──────────────────────────
                    if let last = sessions.first {
                        LastSessionCard(
                            session: last,
                            previousSession: sessions.count > 1 ? sessions[1] : nil
                        ) {
                            if let result = last.decoded() {
                                router.push(.results(result))
                            }
                        }
                        .padding(.bottom, 16)
                    } else {
                        FirstRunCard()
                            .padding(.bottom, 16)
                    }

                    // ── Record strip ──────────────────────────────────────
                    if !sessions.isEmpty {
                        RecordStrip(sessions: sessions)
                            .padding(.bottom, 24)
                    }

                    // ── Training log (needs ≥2 sessions to draw a trend) ──
                    if sessions.count >= 2 {
                        TrainingLogPanel(sessions: sessions)
                            .padding(.bottom, 24)
                    }

                    Spacer(minLength: 30)

                    // ── Actions ───────────────────────────────────────────
                    Button {
                        router.push(.camera)
                    } label: {
                        HStack {
                            Text("Analyze a swim")
                                .font(.grotesk(18, .medium))
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.body.weight(.semibold))
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(DS.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.bottom, 4)

                    if !sessions.isEmpty {
                        Button {
                            router.push(.history)
                        } label: {
                            HStack {
                                Text("History")
                                    .font(.grotesk(15, .medium))
                                    .foregroundStyle(DS.ink)
                                Spacer()
                                Text("\(sessions.count) SESSIONS")
                                    .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                                    .tracking(1.2)
                                    .foregroundStyle(DS.inkTertiary)
                                Image(systemName: "arrow.right")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(DS.inkTertiary)
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, 16)
                            .overlay(alignment: .bottom) { Rectangle().fill(DS.border).frame(height: 1) }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .padding(.top, 6)
                    }

                    // ── Dev tools (DEBUG builds only) ─────────────────────
                    #if DEBUG
                    devTools
                        .padding(.top, 24)
                    #endif

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 24)
                .frame(minHeight: geo.size.height, alignment: .top)
            }
            }
        }
        .fullScreenCover(isPresented: .constant(!hasSeenOnboarding)) { OnboardingView() }
        .navigationBarHidden(true)
        .onAppear {
            #if DEBUG
            if let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
               let found = try? FileManager.default.contentsOfDirectory(at: docsDir, includingPropertiesForKeys: nil)
                   .first(where: { $0.pathExtension.lowercased() == "mp4" }) {
                docsVideoURL = found
            }
            // Launch-argument hooks for automated screenshot capture / testing
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-seedTrainingLog") {
                seedTrainingLog()
            }
            if router.path.isEmpty {
                if args.contains("-demoResults") {
                    router.push(.results(AnalysisResult.demo))
                } else if args.contains("-demoReport") {
                    router.push(.report(AnalysisResult.demo))
                } else if args.contains("-demoCompare") {
                    router.push(.compare(earlier: AnalysisResult.demoEarlier,
                                         later: AnalysisResult.demo))
                } else if args.contains("-openHistory") {
                    router.push(.history)
                } else if let i = args.firstIndex(of: "-analyzeDocs"), i + 1 < args.count,
                          let docsDir = FileManager.default.urls(
                              for: .documentDirectory, in: .userDomainMask).first {
                    let url = docsDir.appendingPathComponent(args[i + 1])
                    if FileManager.default.fileExists(atPath: url.path) {
                        router.push(.analyzing(url))
                    }
                }
            }
            #endif
        }
    }

    // MARK: - Dev tools

    #if DEBUG
    /// Deterministic training-log fixture for simulator screenshots:
    /// replaces the store with three weeks of improving sessions.
    private func seedTrainingLog() {
        sessions.forEach { modelContext.delete($0) }
        let plan: [(daysAgo: Int, score: Int)] = [
            (16, 58), (14, 61), (12, 60), (9, 64), (8, 63),
            (6, 67), (5, 66), (2, 70), (1, 69), (0, 72),
        ]
        for item in plan {
            let base = AnalysisResult.demo
            let result = AnalysisResult(
                id: UUID(),
                score: item.score,
                grade: item.score >= 70 ? "C" : "D",
                strokeCount: base.strokeCount,
                kickRatePerMin: base.kickRatePerMin,
                strokeAsymmetry: base.strokeAsymmetry,
                frameCount: base.frameCount,
                sampledFrames: base.sampledFrames,
                fps: base.fps,
                issues: base.issues,
                tips: base.tips,
                analyzedAt: Calendar.current.date(
                    byAdding: .day, value: -item.daysAgo, to: Date()) ?? Date()
            )
            modelContext.insert(SwimSession(result: result))
        }
    }

    private var devTools: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Dev tools")
            HStack(spacing: 10) {
                Button {
                    if let url = Bundle.main.url(forResource: "swim_test", withExtension: "mp4") {
                        router.push(.analyzing(url))
                    } else {
                        router.push(.results(AnalysisResult.demo))
                    }
                } label: {
                    devButton("Demo", icon: "sparkles")
                }
                Button {
                    showFilePicker = true
                } label: {
                    devButton("Load video", icon: "folder")
                }
                if let mp4 = docsVideoURL {
                    Button {
                        router.push(.analyzing(mp4))
                    } label: {
                        devButton(mp4.lastPathComponent, icon: "play.circle")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                let accessed = url.startAccessingSecurityScopedResource()
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.copyItem(at: url, to: tmp)
                if accessed { url.stopAccessingSecurityScopedResource() }
                router.push(.analyzing(tmp))
            }
        }
    }

    private func devButton(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(DS.inkSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DS.border, lineWidth: 1))
    }
    #endif
}

// MARK: - Training log (sparkline + this-week line)

private struct TrainingLogPanel: View {
    let sessions: [SwimSession]

    private var entries: [TrainingLog.Entry] {
        sessions.map { TrainingLog.Entry(date: $0.analyzedAt, score: $0.score) }
    }

    private var thisWeek: TrainingLog.WeekSummary {
        TrainingLog.summary(for: entries, weekContaining: Date())
    }

    private var delta: Int? {
        TrainingLog.weekOverWeekDelta(for: entries)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Training log")

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
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trainingLogAccessibilityLabel)
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

// MARK: - First-run welcome card

private struct FirstRunCard: View {
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

private struct RecordStrip: View {
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

private struct LastSessionCard: View {
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
