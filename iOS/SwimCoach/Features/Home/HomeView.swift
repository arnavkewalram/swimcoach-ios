import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SwimSession.analyzedAt, order: .reverse) private var sessions: [SwimSession]
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @AppStorage("lastSeenWhatsNewVersion") private var lastSeenWhatsNewVersion: String = ""
    @AppStorage("activeSwimmer") private var activeSwimmer: String = ""
    @State private var showWhatsNew = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var isImporting = false
    #if DEBUG
    @State private var showFilePicker = false
    @State private var docsVideoURL: URL? = nil
    #endif

    /// Sheets presented synchronously in onAppear can silently no-op on
    /// first render — defer past the initial layout pass.
    private func presentWhatsNewSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            showWhatsNew = true
        }
    }

    /// Sessions scoped to the active swimmer ("" = everyone). Falls back
    /// to everyone when the stored swimmer no longer has sessions.
    private var scopedSessions: [SwimSession] {
        guard !activeSwimmer.isEmpty else { return Array(sessions) }
        let scoped = sessions.filter { $0.swimmer == activeSwimmer }
        return scoped.isEmpty ? Array(sessions) : scoped
    }

    private var presentSwimmers: [String] {
        Array(Set(sessions.map(\.swimmer).filter { !$0.isEmpty })).sorted()
    }

    private var focusFault: (name: String, occurrences: Int, window: Int)? {
        // Chronological issue-name lists from stored metadata (no decode)
        let chronological = scopedSessions.reversed().map(\.issueNames)
        guard let name = FocusFault.pick(recentIssueNames: chronological) else { return nil }
        let window = min(FocusFault.window, scopedSessions.count)
        return (name, FocusFault.occurrences(of: name, in: chronological), window)
    }

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
                        .padding(.bottom, presentSwimmers.count > 1 ? 12 : 22)

                    // ── Swimmer scope (appears once >1 swimmer exists) ────
                    if presentSwimmers.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                swimmerScopeChip(label: "Everyone", value: "")
                                ForEach(presentSwimmers, id: \.self) { swimmer in
                                    swimmerScopeChip(label: swimmer, value: swimmer)
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }

                    // ── Last session / first run ──────────────────────────
                    if let last = scopedSessions.first {
                        LastSessionCard(
                            session: last,
                            previousSession: scopedSessions.count > 1 ? scopedSessions[1] : nil
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

                    // ── Primary action (kept above the fold) ──────────────
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
                        .foregroundStyle(DS.onAccent)
                        .padding(.horizontal, 22)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(DS.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.bottom, 24)

                    // ── Record strip ──────────────────────────────────────
                    if !scopedSessions.isEmpty {
                        RecordStrip(sessions: scopedSessions)
                            .padding(.bottom, 24)
                    }

                    // ── Training log (needs ≥2 sessions to draw a trend) ──
                    if scopedSessions.count >= 2 {
                        TrainingLogPanel(sessions: scopedSessions)
                            .padding(.bottom, 24)
                    }

                    // ── Focus fault (recurring in recent sessions) ────────
                    if let focus = focusFault {
                        FocusPanel(faultName: focus.name,
                                   occurrences: focus.occurrences,
                                   windowSize: focus.window) {
                            router.push(.drills(highlightIssue: focus.name))
                        }
                        .padding(.bottom, 24)
                    }

                    Spacer(minLength: 30)

                    // ── Secondary actions ─────────────────────────────────
                    Button {
                        showPhotoPicker = true
                    } label: {
                        SecondaryButtonLabel(
                            title: isImporting ? "Importing…" : "Import a video",
                            icon: "photo.on.rectangle")
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(isImporting)
                    .accessibilityLabel("Import a swim video from your photo library")
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

                    Button {
                        router.push(.drills(highlightIssue: nil))
                    } label: {
                        HStack {
                            Text("Drill library")
                                .font(.grotesk(15, .medium))
                                .foregroundStyle(DS.ink)
                            Spacer()
                            Text("\(DrillCatalog.all.count) DRILLS")
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

                    // ── Dev tools (DEBUG builds only) ─────────────────────
                    #if DEBUG
                    devTools
                        .padding(.top, 24)
                    #endif

                    Button {
                        router.push(.about)
                    } label: {
                        Text("ABOUT SWIMCOACH")
                            .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                            .tracking(1.4)
                            .foregroundStyle(DS.inkTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                    .accessibilityLabel("About SwimCoach")

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 24)
                .frame(minHeight: geo.size.height, alignment: .top)
            }
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .videos)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            isImporting = true
            Task {
                defer { isImporting = false; photoItem = nil }
                do {
                    if let video = try await item.loadTransferable(type: ImportedVideo.self) {
                        router.push(.analyzing(video.url))
                    }
                } catch {
                    AppLog.storage.error("Photo import failed: \(error.localizedDescription)")
                }
            }
        }
        .fullScreenCover(isPresented: .constant(!hasSeenOnboarding)) { OnboardingView() }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewSheet {
                lastSeenWhatsNewVersion = WhatsNew.currentVersion
                showWhatsNew = false
            }
            .presentationDetents([.large, .medium])
            .presentationDragIndicator(.visible)
        }
        .navigationBarHidden(true)
        .onAppear {
            // What's-new: fresh installs just adopt the current version
            // (onboarding covers them); upgrades get the sheet once.
            // -suppressWhatsNew keeps automated UI flows deterministic.
            if ProcessInfo.processInfo.arguments.contains("-suppressWhatsNew") {
                lastSeenWhatsNewVersion = WhatsNew.currentVersion
            } else if !hasSeenOnboarding || lastSeenWhatsNewVersion.isEmpty {
                if hasSeenOnboarding == false { lastSeenWhatsNewVersion = WhatsNew.currentVersion }
                else if lastSeenWhatsNewVersion.isEmpty {
                    // Pre-feature installs have seen onboarding but never
                    // stored a version — they're upgraders: show it.
                    presentWhatsNewSoon()
                }
            } else if WhatsNew.shouldShow(current: WhatsNew.currentVersion,
                                          lastSeen: lastSeenWhatsNewVersion) {
                presentWhatsNewSoon()
            }
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
                if args.contains("-demoResultsSaved") {
                    seedTrainingLog()
                    // Fetch fresh — the @Query snapshot predates the seed
                    if let latest = try? modelContext.fetch(
                        FetchDescriptor<SwimSession>(
                            sortBy: [SortDescriptor(\.analyzedAt, order: .reverse)])).first,
                       let decoded = latest.decoded() {
                        router.push(.results(decoded))
                    }
                }
                if args.contains("-demoResults") {
                    router.push(.results(AnalysisResult.demo))
                } else if args.contains("-demoReport") {
                    router.push(.report(AnalysisResult.demo))
                } else if args.contains("-demoCompare") {
                    router.push(.compare(earlier: AnalysisResult.demoEarlier,
                                         later: AnalysisResult.demo))
                } else if args.contains("-openHistory") {
                    router.push(.history)
                } else if args.contains("-openAbout") {
                    router.push(.about)
                } else if let i = args.firstIndex(of: "-openDrills") {
                    let issue = i + 1 < args.count && !args[i + 1].hasPrefix("-")
                        ? args[i + 1] : nil
                    router.push(.drills(highlightIssue: issue))
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

    private func swimmerScopeChip(label: String, value: String) -> some View {
        let isOn = activeSwimmer == value
        return Button {
            activeSwimmer = value
        } label: {
            Text(label.uppercased())
                .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                .tracking(1.0)
                .foregroundStyle(isOn ? DS.onAccent : DS.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isOn ? DS.accent : .clear)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(DS.accent.opacity(isOn ? 0 : 0.5), lineWidth: 1))
        }
        .accessibilityLabel("Show \(label)'s training")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: - Dev tools

    #if DEBUG
    /// Deterministic training-log fixture for simulator screenshots:
    /// replaces the store with three weeks of improving sessions.
    private func seedTrainingLog() {
        sessions.forEach { modelContext.delete($0) }
        // The newest seeded session carries the bundled demo clip through
        // the same write path a real analysis uses (SessionVideoStore
        // .persist — bundle resources resolve to their resource name, no
        // copy), so the video player, issue timeline, and SHARE CARD all
        // render in the -demoResultsSaved / -seedTrainingLog flows.
        let newestID = UUID()
        let seededVideoName = Bundle.main
            .url(forResource: "swim_test", withExtension: "mp4")
            .flatMap { SessionVideoStore.persist($0, for: newestID) }
        let plan: [(daysAgo: Int, score: Int)] = [
            (16, 58), (14, 61), (12, 60), (9, 64), (8, 63),
            (6, 67), (5, 66), (2, 70), (1, 69), (0, 72),
        ]
        for item in plan {
            let base = AnalysisResult.demo
            // Low Kick Rate fades out in recent sessions (improving trend);
            // the other faults persist.
            let issues = item.daysAgo <= 6
                ? base.issues.filter { $0.name != "low_kick_rate" }
                : base.issues
            let isNewest = item.daysAgo == 0
            let result = AnalysisResult(
                id: isNewest ? newestID : UUID(),
                score: item.score,
                grade: item.score >= 70 ? "C" : "D",
                strokeCount: base.strokeCount,
                kickRatePerMin: base.kickRatePerMin,
                strokeAsymmetry: base.strokeAsymmetry,
                frameCount: base.frameCount,
                sampledFrames: base.sampledFrames,
                fps: base.fps,
                issues: issues,
                tips: base.tips,
                analyzedAt: Calendar.current.date(
                    byAdding: .day, value: -item.daysAgo, to: Date()) ?? Date(),
                // Video + timeline data on the newest session only — it is
                // the one -demoResultsSaved opens, and history rows stay
                // representative of legacy video-less sessions.
                videoFileName: isNewest ? seededVideoName : nil,
                keypointFrames: isNewest ? base.keypointFrames : nil,
                issueWindows: isNewest ? base.issueWindows : nil,
                durationSeconds: isNewest ? base.durationSeconds : nil
            )
            let session = SwimSession(result: result)
            session.swimmer = item.daysAgo % 2 == 0 ? "Arnav" : "Maya"
            if item.daysAgo == 0 {
                session.name = "Threshold Tuesday"
                session.notes = "Worked on high-elbow catch; felt strong"
            }
            modelContext.insert(session)
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
