import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
#if DEBUG
import AVFoundation
#endif

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
    /// Clips adopted into the session store that no analysis ever claimed.
    /// Derived from the filesystem, so it is refreshed on every return to
    /// Home rather than cached across the app's lifetime.
    @State private var unfinishedTakes: [UnfinishedTakes.Take] = []
    #if DEBUG
    @State private var showFilePicker = false
    @State private var docsVideoURL: URL? = nil
    /// File name the compare demo last wrote into the session store, so the
    /// next visit to Home can take it back out again. See
    /// `sweepDemoCompareClip`.
    @AppStorage("debugDemoCompareClipName") private var demoCompareClipName: String = ""
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
                        PrimaryButtonLabel(title: "Analyze a swim")
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.bottom, 24)

                    // ── Unfinished takes (absent at zero) ─────────────────
                    if !unfinishedTakes.isEmpty {
                        UnfinishedTakesStrip(takes: unfinishedTakes) {
                            router.push(.unfinishedTakes)
                        }
                        .padding(.bottom, 24)
                    }

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
                                   windowSize: focus.window,
                                   onDrills: {
                                       router.push(.drills(highlightIssue: focus.name))
                                   },
                                   onHistory: {
                                       router.push(.fault(name: focus.name))
                                   })
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
                        // External source: analysis copies it into the store
                        // on success, under the id minted here.
                        router.push(.analyzing(PendingClip(external: video.url)))
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
        // First paint, and every return to Home: analyzing a take claims it,
        // deleting one removes it, and recording adds one.
        .task(id: router.path.count) { refreshUnfinishedTakes() }
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
            if args.contains("-seedDrillPractice") {
                seedDrillPractice()
            }
            // After the sessions exist (these clips are claimed BY them) and
            // before the takes, which it would otherwise wipe.
            if args.contains("-seedStoredClips") {
                seedStoredClips()
            }
            if args.contains("-seedUnfinishedTakes") {
                seedUnfinishedTakes()
            }
            // Before the takes list is derived, not after: the demo clip is
            // not a lap anybody filmed, so it must never reach it.
            sweepDemoCompareClip()
            refreshUnfinishedTakes()
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
                } else if let i = args.firstIndex(of: "-demoCompare") {
                    let mode = i + 1 < args.count && !args[i + 1].hasPrefix("-")
                        ? args[i + 1] : ""
                    openCompareDemo(mode: mode)
                } else if args.contains("-demoReview") {
                    // The review screen is only reachable by recording, which
                    // the simulator can't do — open it directly on the bundled
                    // clip. Passed as an external clip so Retake can't delete
                    // a bundle resource.
                    if let url = Bundle.main.url(forResource: "swim_test", withExtension: "mp4") {
                        router.push(.review(PendingClip(external: url)))
                    }
                } else if args.contains("-openTakes") {
                    router.push(.unfinishedTakes)
                } else if args.contains("-openHistory") {
                    router.push(.history)
                } else if args.contains("-openAbout") {
                    router.push(.about)
                } else if let i = args.firstIndex(of: "-openDrills") {
                    let issue = i + 1 < args.count && !args[i + 1].hasPrefix("-")
                        ? args[i + 1] : nil
                    router.push(.drills(highlightIssue: issue))
                } else if let i = args.firstIndex(of: "-openFault"), i + 1 < args.count {
                    // A fault page is otherwise only reachable by tapping a
                    // bar in a chart, which automated capture cannot aim at.
                    router.push(.fault(name: args[i + 1]))
                } else if let i = args.firstIndex(of: "-analyzeDocs"), i + 1 < args.count,
                          let docsDir = FileManager.default.urls(
                              for: .documentDirectory, in: .userDomainMask).first {
                    let url = docsDir.appendingPathComponent(args[i + 1])
                    if FileManager.default.fileExists(atPath: url.path) {
                        router.push(.analyzing(PendingClip(external: url)))
                    }
                }
            }
            #endif
        }
    }

    /// A directory listing plus the session-id column the @Query already
    /// holds — no result blob is decoded, so this stays cheap enough to run
    /// on every appearance.
    private func refreshUnfinishedTakes() {
        unfinishedTakes = SessionVideoStore.unfinishedTakes(
            referencedIDs: Set(sessions.map(\.id.uuidString)))
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
                // Stroke mechanics track the score story so the History
                // STROKE MECHANICS panel demos: stroke rate eases down and
                // kick rate builds as technique improves.
                strokeCount: base.strokeCount + (72 - item.score) / 2,
                kickRatePerMin: base.kickRatePerMin - Double(72 - item.score),
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
                // The three oldest sessions stay duration-less — legacy rows
                // saved before durations were stored — so the stroke-rate
                // series demos its gap behavior.
                durationSeconds: item.daysAgo >= 12 ? nil : base.durationSeconds
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

    /// Deterministic fixture for the drill library's "is it working?"
    /// read-out: twelve swims plus a practice log arranged so that every
    /// `DrillEffect` state lands on exactly one card, in catalog order —
    ///
    ///   01 Fingertip Drag    not tracked yet   (never marked done)
    ///   02 Catch-Up          nothing to track  (targets faults never seen)
    ///   03 Fist Drill        showing up more   (0/6 → 5/6)
    ///   04 Single-Arm        no baseline       (2 swims predate the tap)
    ///   05 Superman Glide    about the same    (6/6 → 6/6)
    ///   06 6-Kick Switch     not enough swims  (first tap is right now)
    ///   07 Vertical Kicking  nothing to track
    ///   08 Side Flutter      no baseline       (tap predates every swim)
    ///   09 2-Beat Timing     showing up less   (6/6 → 0/6)
    ///   10 Pull-Buoy Pull    not tracked yet
    ///
    /// Replaces the store, like `-seedTrainingLog`. Swims are back-dated an
    /// extra hour so the newest one is strictly older than a tap made at
    /// seed time — the boundary is an instant, not a day.
    private func seedDrillPractice() {
        sessions.forEach { modelContext.delete($0) }
        try? modelContext.delete(model: DrillPracticeEvent.self)
        let now = Date()

        // `body_sag` runs through every swim; `low_kick_rate` stops at the
        // 12-day boundary; `left_elbow_collapse` starts after it.
        let plan: [(daysAgo: Int, score: Int)] = [
            (24, 55), (22, 57), (20, 56), (18, 60), (15, 62), (13, 61),
            (10, 66), (8, 65), (6, 70), (4, 69), (2, 74), (0, 78),
        ]
        for item in plan {
            var faults = ["body_sag"]
            if item.daysAgo > 12 { faults.append("low_kick_rate") }
            if item.daysAgo < 10 { faults.append("left_elbow_collapse") }
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
                issues: FeedbackEngine.decode(probabilities: probabilities(for: faults)),
                tips: base.tips,
                analyzedAt: now.addingTimeInterval(-(Double(item.daysAgo) * 86_400 + 3_600)),
                durationSeconds: base.durationSeconds)
            let session = SwimSession(result: result)
            session.swimmer = "Arnav"
            modelContext.insert(session)
        }

        // Practice log. The FIRST tap on a drill is its boundary, so only
        // the earliest entry per drill decides which side a swim lands on.
        let log: [(drill: String, daysAgo: [Double])] = [
            ("two-beat-timing", [12, 9, 6, 3]),
            ("superman-glide", [12, 5]),
            ("fist-drill", [12]),
            ("catch-up", [12]),
            ("vertical-kick", [12]),
            ("single-arm", [21, 4]),
            ("side-flutter", [26, 11]),
            ("six-kick-switch", [0]),
        ]
        for entry in log {
            for daysAgo in entry.daysAgo {
                // Stamped like a real tap, and with the swimmer the seeded
                // sessions carry — the fixture has to survive its own
                // scoping rule, not just the default "everyone" scope.
                modelContext.insert(DrillPracticeEvent(
                    drillID: entry.drill,
                    date: now.addingTimeInterval(-daysAgo * 86_400),
                    swimmer: "Arnav"))
            }
        }
    }

    /// Probability vector that decodes to exactly `faults`, so seeded
    /// sessions carry real catalog metadata instead of hand-built issues.
    private func probabilities(for faults: [String]) -> [Float] {
        let present = Set(faults)
        return FeedbackEngine.issueNames.map { present.contains($0) ? 0.62 : 0.05 }
    }

    /// Open Compare in one of its three footage states — the simulator can't
    /// record, so the only way to see the side-by-side band is to hand it
    /// clips here.
    ///
    /// `""` (bare `-demoCompare`) keeps the original fixture, which is also
    /// the one-clip-missing case: `demoEarlier` has no video. `both` attaches
    /// clips to both sides, and `none` strips them.
    private func openCompareDemo(mode: String) {
        var earlier = AnalysisResult.demoEarlier
        var later = AnalysisResult.demo
        switch mode {
        case "none":
            later.videoFileName = nil
            router.push(.compare(earlier: earlier, later: later))
        case "both":
            // Deliberately NOT the same file twice: proportional sync is
            // invisible on two clips of equal length. The earlier swim gets a
            // 5-second cut of the 8-second bundled clip, so the band has a
            // real length mismatch to hold together.
            Task {
                sweepDemoCompareClip()
                let name = await Self.trimmedDemoClip(id: earlier.id, seconds: 5)
                demoCompareClipName = name ?? ""
                earlier.videoFileName = name
                router.push(.compare(earlier: earlier, later: later))
            }
        default:
            router.push(.compare(earlier: earlier, later: later))
        }
    }

    /// Take the compare demo's clip back out of the session store.
    ///
    /// `trimmedDemoClip` writes into the real store under
    /// `AnalysisResult.demoEarlier.id` — a fresh UUID every launch — and no
    /// `SwimSession` ever claims it, so `UnfinishedTakes` classified it as a
    /// recoverable take and Home offered the user back a lap they never
    /// filmed, one more per `-demoCompare both` launch, each held for a
    /// week. Sweeping on every Home appearance means the file exists only
    /// while the demo that needs it is on screen, and the name is remembered
    /// across launches so a clip written before a crash is still collected.
    private func sweepDemoCompareClip() {
        guard !demoCompareClipName.isEmpty else { return }
        SessionVideoStore.delete(fileName: demoCompareClipName)
        demoCompareClipName = ""
    }

    /// A shortened copy of the bundled cartoon, written into the session store
    /// under `id` so it resolves like any other session video. Nil below
    /// iOS 18, where the non-deprecated export API does not exist — the demo
    /// then falls back to a one-clip pair, which is a state worth seeing too.
    private static func trimmedDemoClip(id: UUID, seconds: Double) async -> String? {
        guard #available(iOS 18.0, *),
              let source = Bundle.main.url(forResource: "swim_test", withExtension: "mp4")
        else { return nil }
        let name = "\(id.uuidString).mp4"
        let dest = SessionVideoStore.directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        guard let export = AVAssetExportSession(asset: AVURLAsset(url: source),
                                                presetName: AVAssetExportPresetHighestQuality)
        else { return nil }
        export.timeRange = CMTimeRange(start: .zero,
                                       duration: CMTime(seconds: seconds, preferredTimescale: 600))
        do {
            try await export.export(to: dest, as: .mp4)
            return name
        } catch {
            AppLog.storage.error("Demo clip trim failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Exactly two unfinished takes, for simulator screenshots and route
    /// tests: recording is the only thing that produces them for real, and the
    /// simulator has no camera.
    ///
    /// Replaces whatever was waiting rather than adding to it, so repeated
    /// launches keep giving the same fixture. Copies the bundled clip into the
    /// session store under fresh ids (so the `<result-id>.<ext>` invariant
    /// holds) and back-dates them — which also exercises retention for real:
    /// both land inside the window, so the launch sweep must leave them alone.
    private func seedUnfinishedTakes() {
        SessionVideoStore.unfinishedTakes(referencedIDs: Set(sessions.map(\.id.uuidString)))
            .forEach(SessionVideoStore.delete)
        guard let source = Bundle.main.url(forResource: "swim_test", withExtension: "mp4")
        else { return }
        // Newest first once classified: hours old, then two days old.
        for hoursAgo in [5, 50] {
            let id = UUID()
            let dest = SessionVideoStore.directory
                .appendingPathComponent("\(id.uuidString).mp4")
            try? FileManager.default.removeItem(at: dest)
            guard (try? FileManager.default.copyItem(at: source, to: dest)) != nil else { continue }
            let filmedAt = Date().addingTimeInterval(-Double(hoursAgo) * 3600)
            try? FileManager.default.setAttributes(
                [.modificationDate: filmedAt], ofItemAtPath: dest.path)
        }
    }

    /// Simulator fixture for About's clip-storage section. Recording is the
    /// only thing that fills the store for real and the simulator has no
    /// camera, so this copies the bundled clip in under the ids of the four
    /// newest saved sessions — the `<result-id>.<ext>` invariant, hence
    /// genuinely *claimed* files, not lookalikes — and back-dates them across
    /// the offered cutoffs so every age row prices a different set.
    ///
    /// Each session is repointed at its own copy too, so the fixture is the
    /// real relationship end to end: Results plays these clips before the
    /// delete and drops its video section after it.
    ///
    /// Saves and then fetches rather than reading `sessions`: `-seedTrainingLog`
    /// runs a few lines above, so the `@Query` snapshot still predates it and
    /// its inserts are not yet on disk. Without the save the fetch comes back
    /// empty and the fixture silently writes nothing.
    private func seedStoredClips() {
        // `-seedTrainingLog` replaces the sessions but nothing replaces the
        // video store, so clips claimed by the sessions it just deleted would
        // linger as orphans and be counted alongside this fixture — the store
        // has to start from a known state or the numbers are whatever the
        // previous run happened to leave. Runs before `-seedUnfinishedTakes`
        // so the takes it writes survive this.
        SessionVideoStore.removeAll()
        try? modelContext.save()
        guard let source = Bundle.main.url(forResource: "swim_test", withExtension: "mp4"),
              let saved = try? modelContext.fetch(FetchDescriptor<SwimSession>(
                  sortBy: [SortDescriptor(\.analyzedAt, order: .reverse)])),
              !saved.isEmpty
        else { return AppLog.storage.error("-seedStoredClips found no sessions to claim clips") }
        for (session, daysAgo) in zip(saved, [1, 45, 120, 500]) {
            let name = "\(session.id.uuidString).mp4"
            let dest = SessionVideoStore.directory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            guard (try? FileManager.default.copyItem(at: source, to: dest)) != nil else { continue }
            try? FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-Double(daysAgo) * 24 * 60 * 60)],
                ofItemAtPath: dest.path)
            guard var result = session.decoded() else { continue }
            result.videoFileName = name
            session.resultData = (try? JSONEncoder().encode(result)) ?? session.resultData
        }
    }

    private var devTools: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Dev tools")
            HStack(spacing: 10) {
                Button {
                    if let url = Bundle.main.url(forResource: "swim_test", withExtension: "mp4") {
                        router.push(.analyzing(PendingClip(external: url)))
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
                        router.push(.analyzing(PendingClip(external: mp4)))
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
                router.push(.analyzing(PendingClip(external: tmp)))
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
