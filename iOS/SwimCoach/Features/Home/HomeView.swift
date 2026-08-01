import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(AppRouter.self) private var router
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

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Masthead ──────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        Text(greeting.uppercased())
                            .font(.sectionLabel)
                            .tracking(2.0)
                            .foregroundStyle(DS.inkTertiary)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("SwimCoach")
                                .font(.grotesk(34, .bold))
                                .foregroundStyle(DS.ink)
                            Image(systemName: "figure.pool.swim")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(DS.accent)
                                .accessibilityHidden(true)
                        }
                        Text("Technique analysis, on device")
                            .font(.system(size: 13))
                            .foregroundStyle(DS.inkSecondary)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 24)

                    LaneRule()
                        .padding(.bottom, 24)

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

                    // ── Actions ───────────────────────────────────────────
                    Button {
                        router.push(.camera)
                    } label: {
                        PrimaryButtonLabel(title: "Analyze a swim", icon: "video.fill")
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.bottom, 10)

                    if !sessions.isEmpty {
                        Button {
                            router.push(.history)
                        } label: {
                            SecondaryButtonLabel(title: "History · \(sessions.count)",
                                                 icon: "clock.arrow.circlepath")
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }

                    // ── Dev tools (DEBUG builds only) ─────────────────────
                    #if DEBUG
                    devTools
                        .padding(.top, 28)
                    #endif

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
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
            if router.path.isEmpty {
                if args.contains("-demoResults") {
                    router.push(.results(AnalysisResult.demo))
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
                .font(.system(size: 11))
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(DS.inkSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DS.border, lineWidth: 1))
    }
    #endif
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
                .font(.system(size: 14))
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
        .padding(.vertical, 14)
        .glassCard()
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
                .padding(.bottom, 14)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(session.score)")
                        .font(.grotesk(52, .bold))
                        .foregroundStyle(DS.ink)
                    Text(session.grade)
                        .font(.grotesk(22, .bold))
                        .foregroundStyle(gradeColor)
                    if let d = delta, d != 0 {
                        Text(d > 0 ? "▲\(d)" : "▼\(-d)")
                            .font(.grotesk(13, .medium))
                            .foregroundStyle(d > 0 ? DS.severityMinor : DS.severityModerate)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DS.inkTertiary)
                        .accessibilityHidden(true)
                }
                .padding(.bottom, 10)

                Text("\(session.issueCount) issue\(session.issueCount == 1 ? "" : "s") · \(session.strokeCount) strokes")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.inkSecondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                    .fill(gradeColor)
                    .frame(width: 4)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Last session: score \(session.score), grade \(session.grade), " +
            "\(session.issueCount) issue\(session.issueCount == 1 ? "" : "s"). Opens full results."
        )
    }
}
