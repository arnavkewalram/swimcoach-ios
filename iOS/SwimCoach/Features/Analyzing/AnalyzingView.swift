import SwiftUI
import SwiftData

struct AnalyzingView: View {
    /// The clip plus the id its result must carry. `SessionVideoStore` names
    /// stored files after that id and the orphan sweeper matches file names
    /// against `SwimSession.id`, so minting a fresh id here would leave a
    /// camera clip — already adopted into the store at review time — looking
    /// like an orphan the moment it was saved.
    let clip: PendingClip
    private var videoURL: URL { clip.url }
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @AppStorage("activeSwimmer") private var activeSwimmer: String = ""

    @State private var progress: Double = 0
    @State private var statusText = "Extracting pose keypoints…"
    @State private var failed = false
    @State private var failureMessage = ""
    @State private var failureKind: AnalysisFailureKind = .footageRejected
    /// Bumped by "Try again". Drives `.task(id:)` so the retry runs inside the
    /// view's own structured task and is cancelled when the view goes away —
    /// a bare `Task { await runAnalysis() }` would outlive the screen and could
    /// still insert a session and navigate from an already-popped view.
    @State private var attempt = 0
    /// Set once a session owns this clip. Until then every way off this
    /// screen is a discard, and the adopted file has to be cleaned up.
    @State private var claimed = false

    // Step tracking: 0=pose, 1=ai, 2=metrics, 3=report, 4=tips
    private var currentStep: Int {
        if progress < 0.65 { return 0 }
        if progress < 0.80 { return 1 }
        if progress < 0.90 { return 2 }
        if progress < 0.97 { return 3 }
        return 4
    }

    private let steps = ["Pose", "AI Model", "Metrics", "Report", "Tips"]

    var body: some View {
        ZStack {
            DS.background.ignoresSafeArea()

            if failed {
                failureView
            } else {
                analysisView
            }
        }
        .navigationBarHidden(true)
        .task(id: attempt) {
            // Bundle-identity check, not filename match — a user file that
            // happens to be named swim_test.mp4 must get real analysis.
            if videoURL == Bundle.main.url(forResource: "swim_test", withExtension: "mp4") {
                await runDemoAnalysis()
            } else {
                await runAnalysis()
            }
        }
    }

    // MARK: - Sub-views

    private var analysisView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button {
                    // Popping cancels the .task; PoseAnalyzer unwinds via
                    // its cancellation flag.
                    discardClipIfUnclaimed()
                    router.popToRoot()
                } label: {
                    Text("CANCEL")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 11))
                        .tracking(1.4)
                        .foregroundStyle(DS.inkSecondary)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Cancel the analysis")
            }
            .padding(.top, 8)

            Spacer()

            Text("ANALYZING")
                .font(.sectionLabel)
                .tracking(2.0)
                .foregroundStyle(DS.accent)
                .padding(.bottom, 8)

            Text("Reading your\nstroke mechanics")
                .font(.grotesk(30, .bold))
                .foregroundStyle(DS.ink)
                .padding(.bottom, 36)

            // Percentage + flat progress rule
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(progress * 100))")
                    .font(.grotesk(64, .bold))
                    .foregroundStyle(DS.ink)
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: Int(progress * 100))
                Text("%")
                    .font(.grotesk(24, .medium))
                    .foregroundStyle(DS.inkTertiary)
            }
            .padding(.bottom, 12)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(DS.border)
                    Rectangle()
                        .fill(DS.accent)
                        .frame(width: geo.size.width * progress)
                        .animation(.linear(duration: 0.3), value: progress)
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
            .padding(.bottom, 32)

            // Step checklist
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    StepRow(index: i, label: step, state: stepState(for: i))
                    if i < steps.count - 1 {
                        Rectangle().fill(DS.border).frame(height: 1)
                    }
                }
            }
            .glassCard()

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
        .accessibilityElement(children: .contain)
    }

    private func stepState(for index: Int) -> StepState {
        if index < currentStep { return .completed }
        if index == currentStep { return .active }
        return .pending
    }

    private var failureView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(DS.severityModerate)
                .padding(.bottom, 20)
                .accessibilityHidden(true)

            Text("ANALYSIS FAILED")
                .font(.sectionLabel)
                .tracking(2.0)
                .foregroundStyle(DS.severityModerate)
                .padding(.bottom, 8)

            Text(failureKind.headline)
                .font(.grotesk(30, .bold))
                .foregroundStyle(DS.ink)
                .padding(.bottom, 14)

            Text(failureMessage)
                .font(.footnote)
                .lineSpacing(3)
                .foregroundStyle(DS.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 32)

            // The failure copy tells the user to re-film, so the screen has to
            // be able to reach the camera. `.navigationBarHidden(true)` removes
            // the system Back button and CANCEL only exists while analyzing —
            // without this stack the screen is a dead end.
            VStack(spacing: 12) {
                ForEach(Array(failureKind.actions.enumerated()), id: \.element) { index, action in
                    Button {
                        perform(action)
                    } label: {
                        if index == 0 {
                            PrimaryButtonLabel(title: action.title, icon: action.icon)
                        } else {
                            SecondaryButtonLabel(title: action.title, icon: action.icon)
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel(action.accessibilityLabel)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private func perform(_ action: AnalysisFailureAction) {
        // "Try again" re-runs against the same file, so only the two exits
        // give the clip up.
        if action != .tryAgain { discardClipIfUnclaimed() }
        switch action {
        case .recordAgain:
            // popToRoot + push, never replaceTop: arriving from the camera
            // leaves [camera, analyzing], so replaceTop would swap Analyzing
            // for a second Camera and stack two of them. NavigationPath is
            // type-erased and cannot be inspected, so this is the only move
            // that is correct from BOTH entry points (Camera and Home's
            // photo picker).
            router.popToRoot()
            router.push(.camera)
        case .backToHome:
            router.popToRoot()
        case .tryAgain:
            // Restart the view's own `.task` rather than spawning a detached
            // one, so leaving mid-retry cancels the work (see `attempt`).
            progress = 0
            failed = false
            attempt += 1
        }
    }

    /// Leaving without a saved session means the clip is rubbish to the app:
    /// drop the adopted file now instead of waiting for the next launch's
    /// orphan sweep. A no-op for clips the store doesn't own (photo imports,
    /// the bundled demo).
    private func discardClipIfUnclaimed() {
        guard !claimed else { return }
        SessionVideoStore.discard(clip)
    }

    // MARK: - Pipeline

    private func runAnalysis() async {
        do {
            // 1 — Pose extraction (0 → 60%)
            let (timedObservations, fps, sampledFrames) = try await PoseAnalyzer.analyze(videoURL: videoURL) { p in
                Task { @MainActor in
                    self.progress = p * 0.60
                    self.statusText = "Extracting pose keypoints… \(Int(p * 100))%"
                }
            }

            let observations = timedObservations.map(\.observation)
            guard !observations.isEmpty else {
                failWith(.noSwimmerDetected)
                return
            }

            guard observations.count >= 10 else {
                failWith(.tooFewFrames(observations.count))
                return
            }

            await update(progress: 0.65, status: "Running SwimTCN model…")

            // 2 — Feature extraction: 3-second windows in the model's timebase
            let effectiveFPS = fps / Double(PoseAnalyzer.sampleRate)
            guard let tensors = FeatureExtractor.extractWindows(
                from: timedObservations, effectiveFPS: effectiveFPS
            ) else {
                failWith(.unusablePoses)
                return
            }

            // 3 — SwimTCN inference (the ML model is the only detection path).
            // Keep per-window probabilities (issue timeline / "see it") and
            // average them for the overall verdict.
            var windows = [IssueWindow]()
            var probSum = [Float](repeating: 0, count: SwimTCNRunner.expectedLabelCount)
            for w in tensors {
                let p = try SwimTCNRunner.shared.predict(tensor: w.tensor)
                windows.append(IssueWindow(start: w.start, end: w.end, probs: p))
                for i in probSum.indices { probSum[i] += p[i] }
            }
            let probs = probSum.map { $0 / Float(tensors.count) }
            let issues = FeedbackEngine.decode(probabilities: probs)
            await update(progress: 0.80, status: "Decoding technique issues…")

            await update(progress: 0.85, status: "Computing stroke metrics…")

            // 4 — Motion metrics
            let metrics = BiomechanicsEngine().metrics(
                from: timedObservations, fps: fps, sampleRate: PoseAnalyzer.sampleRate,
                sampledFrames: sampledFrames
            )

            await update(progress: 0.92, status: "Building report…")

            // 5 — Assemble result (persist the source video first so Results
            // and History can play it back — temp files get reclaimed)
            let score = BiomechanicsEngine.score(from: issues)
            let grade = BiomechanicsEngine.grade(from: score)
            let sortedIssues = issues.sorted { $0.severity > $1.severity }
            // The id was fixed when the clip was created, not here — see
            // `clip`. A camera clip already sits in the store under this
            // name, so `persist` recognises it and skips the copy; photo and
            // bundle sources still get copied, under the same id.
            let resultID = clip.id
            let videoName = SessionVideoStore.persist(videoURL, for: resultID)
            let keypointFrames = KeypointFrame.frames(from: timedObservations)

            var result = AnalysisResult(
                id: resultID,
                score: score,
                grade: grade,
                strokeCount: metrics.strokeCount,
                kickRatePerMin: metrics.kickRatePerMin,
                strokeAsymmetry: metrics.strokeAsymmetry,
                frameCount: observations.count,
                sampledFrames: sampledFrames,
                fps: fps / Double(PoseAnalyzer.sampleRate),
                issues: sortedIssues,
                tips: sortedIssues.prefix(3).map(\.tip),
                analyzedAt: Date(),
                videoFileName: videoName,
                keypointFrames: keypointFrames,
                issueWindows: windows,
                durationSeconds: metrics.durationSeconds
            )

            // 6 — AI coaching tips
            await update(progress: 0.98, status: "Generating coaching tips…")
            let aiTips = await CoachingService.generateTips(for: result)
            if !aiTips.isEmpty {
                result = AnalysisResult(
                    id: result.id, score: result.score, grade: result.grade,
                    strokeCount: result.strokeCount, kickRatePerMin: result.kickRatePerMin,
                    strokeAsymmetry: result.strokeAsymmetry, frameCount: result.frameCount,
                    sampledFrames: result.sampledFrames,
                    fps: result.fps, issues: result.issues, tips: aiTips,
                    analyzedAt: result.analyzedAt,
                    videoFileName: result.videoFileName,
                    keypointFrames: result.keypointFrames,
                    issueWindows: result.issueWindows,
                    durationSeconds: result.durationSeconds
                )
            }

            // 7 — Auto-save session (Results reads saved-state from SwiftData,
            // so a failed save is shown honestly instead of a false checkmark)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                let session = SwimSession(result: result)
                session.swimmer = activeSwimmer
                modelContext.insert(session)
                do {
                    try modelContext.save()
                    // The session now owns the stored clip — leaving this
                    // screen must no longer delete it.
                    claimed = true
                    // A new session changes this week's count — refresh the
                    // goal reminder copy (and skip the week if now met).
                    GoalReminder.reschedule(context: modelContext)
                } catch {
                    AppLog.analysis.error("Session save failed: \(error.localizedDescription)")
                }
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                progress = 1.0
                // replaceTop: Back from Results must not land on this screen —
                // its .task would re-run the whole analysis and save a duplicate.
                Haptics.success()
            router.replaceTop(with: .results(result))
            }

        } catch is CancellationError {
            return  // user left the screen — no failure UI, no side effects
        } catch {
            // Thrown mid-run rather than rejected upfront: this one may well
            // succeed on a second pass, so it is the only branch that keeps
            // "Try again".
            failWith(.unexpected(error))
        }
    }

    // MARK: - Demo pipeline (bundled test video — no real poses needed)

    private func runDemoAnalysis() async {
        // Step 1 — simulate pose extraction
        for i in stride(from: 0.0, through: 0.60, by: 0.04) {
            await update(progress: i, status: "Extracting pose keypoints…")
            try? await Task.sleep(nanoseconds: 80_000_000)
        }

        await update(progress: 0.65, status: "Running SwimTCN model…")
        try? await Task.sleep(nanoseconds: 700_000_000)

        // Step 2 — build realistic issues
        let issues: [TechniqueIssue] = [
            TechniqueIssue(
                name: "body_sag",
                displayName: "Body Sag",
                severity: .major,
                observedValue: 0.88,
                threshold: 0.45,
                description: "Hips and legs sinking below the waterline — creates significant drag.",
                tip: "Press your chest gently down to float your hips. Engage your core every stroke."
            ),
            TechniqueIssue(
                name: "late_hand_entry",
                displayName: "Late Hand Entry",
                severity: .moderate,
                observedValue: 0.61,
                threshold: 0.40,
                description: "Hand entering the water past the head centerline — shortens catch distance.",
                tip: "Reach straight forward from the shoulder, entering between your head and shoulder line."
            ),
            TechniqueIssue(
                name: "low_kick_rate",
                displayName: "Low Kick Rate",
                severity: .minor,
                observedValue: 0.44,
                threshold: 0.50,
                description: "Kick cadence too low — hurts hip rotation timing and forward balance.",
                tip: "Add a 2-beat kick (one kick per arm stroke) to keep your hips rotating."
            ),
        ]

        await update(progress: 0.80, status: "Decoding technique issues…")
        try? await Task.sleep(nanoseconds: 500_000_000)

        await update(progress: 0.87, status: "Computing stroke metrics…")
        try? await Task.sleep(nanoseconds: 400_000_000)

        await update(progress: 0.92, status: "Building report…")
        try? await Task.sleep(nanoseconds: 300_000_000)

        let score = BiomechanicsEngine.score(from: issues)
        let grade = BiomechanicsEngine.grade(from: score)
        let sorted = issues.sorted { $0.severity > $1.severity }

        var result = AnalysisResult(
            id: clip.id,
            score: score,
            grade: grade,
            strokeCount: 16,
            kickRatePerMin: 44.0,
            strokeAsymmetry: 0.14,
            frameCount: 420,
            sampledFrames: 0,
            fps: 30.0,
            issues: sorted,
            tips: sorted.prefix(3).map(\.tip),
            analyzedAt: Date(),
            videoFileName: videoURL.lastPathComponent,   // bundled demo video
            durationSeconds: 14
        )

        // Step 3 — AI coaching tips
        await update(progress: 0.98, status: "Generating coaching tips…")
        let aiTips = await CoachingService.generateTips(for: result)
        if !aiTips.isEmpty {
            result = AnalysisResult(
                id: result.id, score: result.score, grade: result.grade,
                strokeCount: result.strokeCount, kickRatePerMin: result.kickRatePerMin,
                strokeAsymmetry: result.strokeAsymmetry, frameCount: result.frameCount,
                sampledFrames: result.sampledFrames,
                fps: result.fps, issues: result.issues, tips: aiTips,
                analyzedAt: result.analyzedAt,
                videoFileName: result.videoFileName,
                durationSeconds: result.durationSeconds
            )
        }

        guard !Task.isCancelled else { return }
        await MainActor.run {
            let session = SwimSession(result: result)
                session.swimmer = activeSwimmer
                modelContext.insert(session)
            do {
                try modelContext.save()
                claimed = true
                GoalReminder.reschedule(context: modelContext)
            } catch {
                AppLog.analysis.error("Demo session save failed: \(error.localizedDescription)")
            }
        }

        guard !Task.isCancelled else { return }
        await MainActor.run {
            progress = 1.0
            Haptics.success()
            router.replaceTop(with: .results(result))
        }
    }

    @MainActor private func update(progress p: Double, status s: String) {
        withAnimation { progress = p }
        statusText = s
    }

    /// Called straight from the analysis task instead of being fired into a
    /// detached `Task`, so a screen the user already left cannot flash a
    /// failure state after the fact.
    @MainActor private func failWith(_ failure: AnalysisFailure) {
        failureMessage = failure.message
        failureKind = failure.kind
        failed = true
    }
}

// MARK: - Failure kinds & recovery actions

/// A way out of the analysis-failure screen.
enum AnalysisFailureAction: Hashable {
    case tryAgain
    case recordAgain
    case backToHome

    var title: String {
        switch self {
        case .tryAgain: return "Try again"
        case .recordAgain: return "Record again"
        case .backToHome: return "Back to Home"
        }
    }

    var icon: String? {
        switch self {
        case .tryAgain: return "arrow.clockwise"
        case .recordAgain: return "video"
        case .backToHome: return "house"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .tryAgain: return "Try analyzing this video again"
        case .recordAgain: return "Record a new video"
        case .backToHome: return "Go back to Home"
        }
    }
}

/// Why an analysis stopped — decides which recovery actions are honest to offer.
enum AnalysisFailureKind: Hashable {
    /// The clip itself was rejected: no swimmer, too few frames, unusable
    /// poses. `videoURL` is immutable, so re-running is deterministic — the
    /// same file fails the same way every time.
    case footageRejected
    /// Something threw mid-run. A second pass may succeed.
    case transient

    var headline: String {
        switch self {
        case .footageRejected: return "Couldn't read\nthis footage"
        case .transient: return "Analysis\nstopped short"
        }
    }

    /// First entry renders as the primary button.
    ///
    /// A footage rejection deliberately offers NO "Try again": the copy tells
    /// the user to re-film, and retrying the same clip can only reproduce the
    /// same failure.
    var actions: [AnalysisFailureAction] {
        switch self {
        case .footageRejected: return [.recordAgain, .backToHome]
        case .transient: return [.tryAgain, .recordAgain, .backToHome]
        }
    }
}

/// A failure message paired with the kind that decides its recovery actions.
/// Constructed only through the named cases below so no failure site can ship
/// a message without classifying it.
struct AnalysisFailure: Equatable {
    let kind: AnalysisFailureKind
    let message: String

    var actions: [AnalysisFailureAction] { kind.actions }

    static let noSwimmerDetected = AnalysisFailure(
        kind: .footageRejected,
        message: "No horizontal swimmer detected. " +
            "Film from the pool deck at water level with the swimmer's full body in frame. " +
            "The swimmer must be actively stroking above the water line — avoid underwater angles."
    )

    static func tooFewFrames(_ count: Int) -> AnalysisFailure {
        AnalysisFailure(
            kind: .footageRejected,
            message: "Too few swimmer frames detected (\(count)). " +
                "Film from pool deck height at water level, side-on to the swimmer, " +
                "with the full body visible above the waterline. " +
                "Stay within 3–6 m of the swimmer."
        )
    }

    static let unusablePoses = AnalysisFailure(
        kind: .footageRejected,
        message: "Could not prepare the detected poses for analysis. " +
            "Try re-recording with the swimmer's full body clearly visible."
    )

    static func unexpected(_ error: Error) -> AnalysisFailure {
        AnalysisFailure(kind: .transient, message: error.localizedDescription)
    }
}

// MARK: - Step states & row

enum StepState { case completed, active, pending }

private struct StepRow: View {
    let index: Int
    let label: String
    let state: StepState

    var body: some View {
        HStack(spacing: 12) {
            Group {
                switch state {
                case .completed:
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DS.severityMinor)
                case .active:
                    Text(String(format: "%02d", index + 1))
                        .font(.grotesk(12, .bold))
                        .foregroundStyle(DS.accent)
                case .pending:
                    Text(String(format: "%02d", index + 1))
                        .font(.grotesk(12, .medium))
                        .foregroundStyle(DS.inkTertiary)
                }
            }
            .frame(width: 22, alignment: .leading)
            .accessibilityHidden(true)

            Text(label)
                .font(state == .active ? .grotesk(14, .medium) : .system(size: 14))
                .foregroundStyle(state == .pending ? DS.inkTertiary : DS.ink)

            Spacer()

            if state == .active {
                ProgressView()
                    .controlSize(.small)
                    .tint(DS.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(state == .completed ? "done" : state == .active ? "in progress" : "pending")")
    }
}
