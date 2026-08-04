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
    /// Non-nil once the run has stopped for a reason worth showing. Holding
    /// the whole failure (rather than a bool plus loose message/kind fields)
    /// keeps the copy, the checklist and the recovery actions from ever
    /// disagreeing about which failure is on screen.
    @State private var failure: AnalysisFailure?
    /// Bumped by "Try again". Drives `.task(id:)` so the retry runs inside the
    /// view's own structured task and is cancelled when the view goes away —
    /// a bare `Task { await runAnalysis() }` would outlive the screen and could
    /// still insert a session and navigate from an already-popped view.
    @State private var attempt = 0

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

            if let failure {
                failureView(failure)
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
                    // its cancellation flag. The adopted clip stays put:
                    // cancelling an analysis is not a verdict on the footage,
                    // and the take is waiting on Home afterwards.
                    router.popToRoot()
                } label: {
                    Text("CANCEL")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 11))
                        .tracking(1.4)
                        .foregroundStyle(DS.inkSecondary)
                        .padding(.vertical, 10)
                        // 11pt caps + 10pt insets is a ~34pt tap target. The
                        // frame lifts it to the 44pt minimum before
                        // `contentShape` decides what is tappable — after it,
                        // the added area would not take the hit.
                        .frame(minWidth: 44, minHeight: 44)
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

    /// Top-anchored like every other page in the app: masthead, then the
    /// reason, then what to do about it, with the ways out anchored to the
    /// bottom. It used to float between two `Spacer()`s, which left the band
    /// the analyzing screen fills with CANCEL empty — so the transition into
    /// failure read as the header being cut off.
    private func failureView(_ failure: AnalysisFailure) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    failureMasthead(failure)

                    // The diagnosis is the only content the user can act on,
                    // so it carries a body tier rather than the caption tier
                    // the recovery buttons were out-shouting.
                    Text(failure.message)
                        .font(.system(size: 16))
                        .lineSpacing(4)
                        .foregroundStyle(DS.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 24)

                    failureChecklist(failure)

                    runLog
                        .padding(.top, 22)

                    Spacer(minLength: 16)
                }
                // 28pt, matching the analyzing state rather than the 24pt
                // siblings: these two states swap in place, so the measure
                // has to hold still across the swap.
                .padding(.horizontal, 28)
            }
            .scrollBounceBehavior(.basedOnSize)

            failureActions(failure)
        }
    }

    private func failureMasthead(_ failure: AnalysisFailure) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("ANALYSIS FAILED")
                    .font(.sectionLabel)
                    .tracking(2.0)
                    .foregroundStyle(DS.severityModerate)
                Spacer(minLength: 8)
                // Replaces a stock alarm triangle that repeated, in the same
                // colour, what the label beneath it already said. A meet
                // sheet marks a swim that did not count with a stamped code,
                // so this slot carries one — and it fills the same trailing
                // register as Review's "TAKE · 0:12" and Home's date.
                FailureStamp(code: failure.kind.stamp)
            }
            .padding(.top, 14)

            Text(failure.kind.headline)
                .font(.grotesk(30, .bold))
                .foregroundStyle(DS.ink)
                .padding(.top, 10)
                .padding(.bottom, 16)

            LaneRule()
                .padding(.bottom, 18)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analysis failed. \(failure.kind.headline.replacingOccurrences(of: "\n", with: " ")).")
    }

    /// The advice is genuinely actionable — "Record again" reaches the camera —
    /// so it gets the numbered card the analyzing steps and Review's framing
    /// checks already use, instead of a paragraph of prose.
    private func failureChecklist(_ failure: AnalysisFailure) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: failure.checklistTitle)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(failure.checklist.enumerated()), id: \.offset) { index, item in
                    RequirementRow(index: index, text: item)
                    if index < failure.checklist.count - 1 {
                        Rectangle().fill(DS.border).frame(height: 1)
                    }
                }
            }
            .glassCard()
        }
    }

    /// The 01–05 pipeline the analyzing state was stepping through, frozen at
    /// the point the run stopped — five lanes, with the one it died in marked.
    ///
    /// This is the screen's data register, and it answers the question the old
    /// failure screen left open: how far did it actually get? Kept to a strip
    /// rather than the full row card so that evidence stays below the
    /// actionable checklist in weight as well as in order.
    private var runLog: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Run log")

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(steps.indices, id: \.self) { i in
                        VStack(spacing: 6) {
                            Text(String(format: "%02d", i + 1))
                                .font(.grotesk(11, i == currentStep ? .bold : .medium))
                                .foregroundStyle(laneColor(i, forRule: false))
                            Rectangle()
                                .fill(laneColor(i, forRule: true))
                                .frame(height: 3)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Text("STOPPED AT")
                        .font(.sectionLabel)
                        .tracking(1.4)
                        .foregroundStyle(DS.inkTertiary)
                    Text("\(String(format: "%02d", currentStep + 1)) · \(steps[currentStep])")
                        .font(.grotesk(13, .medium))
                        .foregroundStyle(DS.ink)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .glassCard()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Run log: stopped at step \(currentStep + 1) of \(steps.count), \(steps[currentStep])")
        }
    }

    /// `progress` is left where the run died, so the step that was in flight
    /// is the one that stopped: cleared lanes behind it, untouched ahead.
    /// Unreached lanes take the muted mark, but their numerals take the
    /// tertiary ink — a hairline-weight token is unreadable as type.
    private func laneColor(_ index: Int, forRule: Bool) -> Color {
        if index < currentStep { return DS.severityMinor }
        if index == currentStep { return DS.severityModerate }
        return forRule ? DS.markMuted : DS.inkTertiary
    }

    /// The failure copy tells the user to re-film, so the screen has to be able
    /// to reach the camera. `.navigationBarHidden(true)` removes the system
    /// Back button and CANCEL only exists while analyzing — without this stack
    /// the screen is a dead end.
    ///
    /// Three buttons at one weight read as three equal choices; the tiers keep
    /// the next-best move ahead of the escape hatch.
    private func failureActions(_ failure: AnalysisFailure) -> some View {
        VStack(spacing: 10) {
            LaneRule()
                .padding(.bottom, 4)

            ForEach(failure.actions, id: \.self) { action in
                Button {
                    perform(action)
                } label: {
                    switch failure.kind.tier(for: action) {
                    case .primary:
                        // The only primary in the app that overrides the
                        // default `arrow.right`: recovery actions name
                        // themselves (re-film, retry) rather than pointing at
                        // a next screen, so the action's own glyph earns the
                        // trailing slot.
                        PrimaryButtonLabel(title: action.title, icon: action.icon)
                    case .secondary:
                        SecondaryButtonLabel(title: action.title, icon: action.icon)
                    case .tertiary:
                        Text(action.title.uppercased())
                            .font(.custom(GroteskWeight.medium.postScriptName, size: 11))
                            .tracking(1.4)
                            .foregroundStyle(DS.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                }
                // A custom ButtonStyle replaces the system one wholesale, so
                // the tertiary label keeps its own foreground instead of
                // picking up the default accent tint.
                .buttonStyle(ScaleButtonStyle())
                .accessibilityLabel(action.accessibilityLabel)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(DS.background)
    }

    private func perform(_ action: AnalysisFailureAction) {
        // No exit from here deletes the clip. A failed analysis is precisely
        // the case the retention window exists for: the user filmed a real
        // lap, the app could not read it, and destroying the footage on the
        // way out means they filmed it for nothing. The take stays in the
        // store, Home surfaces it as unfinished, and the only immediate
        // deletions are the two places the user actually says no — Retake on
        // the review screen, and Delete on the recovery screen.
        //
        // Clips the store does not own (photo imports) are unaffected either
        // way: the original is still in the library the user picked it from.
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
            failure = nil
            attempt += 1
        }
    }

    // MARK: - Pipeline

    private func runAnalysis() async {
        do {
            // 1 — Pose extraction (0 → 60%)
            let (timedObservations, fps, sampledFrames) = try await PoseAnalyzer.analyze(videoURL: videoURL) { p in
                Task { @MainActor in
                    self.progress = p * 0.60
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

            await update(progress: 0.65)

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
            await update(progress: 0.80)

            await update(progress: 0.85)

            // 4 — Motion metrics
            let metrics = BiomechanicsEngine().metrics(
                from: timedObservations, fps: fps, sampleRate: PoseAnalyzer.sampleRate,
                sampledFrames: sampledFrames
            )

            await update(progress: 0.92)

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
            await update(progress: 0.98)
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
                    // The session now owns the stored clip: its id matches the
                    // file's name, so the sweeper reads it as claimed and the
                    // take drops off the unfinished list. A failed save leaves
                    // it unclaimed — and therefore recoverable — instead.
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
            await update(progress: i)
            try? await Task.sleep(nanoseconds: 80_000_000)
        }

        await update(progress: 0.65)
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

        await update(progress: 0.80)
        try? await Task.sleep(nanoseconds: 500_000_000)

        await update(progress: 0.87)
        try? await Task.sleep(nanoseconds: 400_000_000)

        await update(progress: 0.92)
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
        await update(progress: 0.98)
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

    @MainActor private func update(progress p: Double) {
        withAnimation { progress = p }
    }

    /// Called straight from the analysis task instead of being fired into a
    /// detached `Task`, so a screen the user already left cannot flash a
    /// failure state after the fact.
    @MainActor private func failWith(_ failure: AnalysisFailure) {
        self.failure = failure
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

    /// Visual weight for one of `actions`. Rendering the stack at a single
    /// weight made the escape hatch compete with the next-best move; Home is
    /// always the quiet way out, and only the lead action is loud.
    func tier(for action: AnalysisFailureAction) -> AnalysisActionTier {
        if action == .backToHome { return .tertiary }
        return action == actions.first ? .primary : .secondary
    }

    /// The meet-sheet stamp for a swim that did not count.
    var stamp: String {
        switch self {
        case .footageRejected: return "NO READ"
        case .transient: return "STOPPED"
        }
    }
}

/// How loudly a recovery action is drawn.
enum AnalysisActionTier { case primary, secondary, tertiary }

/// A failure message paired with the kind that decides its recovery actions.
/// Constructed only through the named cases below so no failure site can ship
/// a message without classifying it.
struct AnalysisFailure: Equatable {
    let kind: AnalysisFailureKind
    /// The diagnosis, one sentence, in the app's voice — rendered at body
    /// tier. Advice belongs in `checklist`, not stapled onto the end of this.
    let message: String
    /// What to do about it, as register lines rather than prose. Every
    /// failure carries at least one: a screen that can reach the camera owes
    /// the user something to change before they film again.
    let checklist: [String]
    let checklistTitle: String

    var actions: [AnalysisFailureAction] { kind.actions }

    // MARK: Footage rejections

    static let noSwimmerDetected = AnalysisFailure(
        kind: .footageRejected,
        message: "No horizontal swimmer detected anywhere in this clip.",
        checklist: [
            "Film side-on from the pool deck, camera at water level",
            "Keep the full body in frame, head to feet",
            "Capture strokes above the waterline — not underwater angles",
        ],
        checklistTitle: "What the model needs"
    )

    static func tooFewFrames(_ count: Int) -> AnalysisFailure {
        AnalysisFailure(
            kind: .footageRejected,
            message: "Too few frames held a swimmer (\(count)) — not enough to read a stroke.",
            checklist: [
                "Film side-on at pool-deck height, camera at water level",
                "Stay within 3–6 m so the full body stays in frame",
                "Record at least one full length at a normal pace",
            ],
            checklistTitle: "What the model needs"
        )
    }

    static let unusablePoses = AnalysisFailure(
        kind: .footageRejected,
        message: "A swimmer was found, but the detected poses were too broken to analyze.",
        checklist: [
            "Keep the whole body clearly visible for the whole length",
            "Pan smoothly with the swimmer instead of holding still",
            "Avoid heavy splash, surface glare and crossing swimmers",
        ],
        checklistTitle: "What the model needs"
    )

    /// The file itself is not a video the reader can open. Deterministic:
    /// `videoURL` is immutable, so a second pass re-reads the same bytes and
    /// fails identically — this is a footage rejection, not a retry.
    private static func unreadableRecording(_ message: String) -> AnalysisFailure {
        AnalysisFailure(
            kind: .footageRejected,
            message: message,
            checklist: [
                "Record the clip with SwimCoach's own camera",
                "Or import a video the Photos app can play back",
            ],
            checklistTitle: "What to try"
        )
    }

    // MARK: Mid-run errors

    /// Classifies a thrown error rather than calling everything transient.
    ///
    /// `.noVideoTrack` is a property of the file: no amount of retrying puts a
    /// video track into it, so offering "Try again" was a lie the screen told
    /// every time a non-video landed here. `.readerFailed` keeps the retry —
    /// `startReading()` also fails under momentary resource pressure, and a
    /// wasted retry is cheaper there than a wasted re-film. Everything else
    /// (CoreML load, inference, persistence) is genuinely worth a second pass.
    static func unexpected(_ error: Error) -> AnalysisFailure {
        if let readError = error as? AnalysisError, case .noVideoTrack = readError {
            return unreadableRecording(readError.localizedDescription)
        }
        return AnalysisFailure(
            kind: .transient,
            message: error.localizedDescription,
            checklist: [
                "The clip is still on your device — retrying costs nothing",
                "Close and reopen SwimCoach if it stops again",
                "Free up storage if your device is nearly full",
            ],
            checklistTitle: "What to try"
        )
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

            // Grotesk in every state: these are stage names in the data
            // register, and swapping to SF for pending/completed made the
            // letterforms visibly reflow as each step advanced. Weight — not
            // family — carries the state.
            Text(label)
                .font(.grotesk(14, state == .active ? .medium : .regular))
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

// MARK: - Failure checklist row & stamp

/// One numbered requirement on the failure screen — the same register as the
/// analyzing steps above and Review's framing checks, so the advice reads as
/// part of the sheet rather than as a paragraph of apology. Grotesk numerals
/// carry the data register; SF carries the sentence.
private struct RequirementRow: View {
    let index: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(String(format: "%02d", index + 1))
                .font(.grotesk(12, .medium))
                .foregroundStyle(DS.accent)
                .frame(width: 22, alignment: .leading)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 14))
                .lineSpacing(2)
                .foregroundStyle(DS.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }
}

/// The trailing masthead mark: a stamped code, the way a meet sheet annotates
/// a swim that did not count. Replaces a stock alarm triangle that repeated
/// the label beneath it in the same colour.
private struct FailureStamp: View {
    let code: String

    var body: some View {
        Text(code)
            .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
            .tracking(1.6)
            .foregroundStyle(DS.severityModerate)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(DS.severityModerate.opacity(0.55), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}
