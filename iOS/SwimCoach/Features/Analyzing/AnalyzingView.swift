import SwiftUI
import SwiftData

struct AnalyzingView: View {
    let videoURL: URL
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext

    @State private var progress: Double = 0
    @State private var statusText = "Extracting pose keypoints…"
    @State private var failed = false
    @State private var failureMessage = ""

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
        .task {
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

            Text("Couldn't read\nthis footage")
                .font(.grotesk(30, .bold))
                .foregroundStyle(DS.ink)
                .padding(.bottom, 14)

            Text(failureMessage)
                .font(.footnote)
                .lineSpacing(3)
                .foregroundStyle(DS.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 32)

            Button {
                failed = false
                Task { await runAnalysis() }
            } label: {
                PrimaryButtonLabel(title: "Try again")
            }
            .buttonStyle(ScaleButtonStyle())

            Spacer()
        }
        .padding(.horizontal, 28)
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
                failWith(
                    "No horizontal swimmer detected. " +
                    "Film from the pool deck at water level with the swimmer's full body in frame. " +
                    "The swimmer must be actively stroking above the water line — avoid underwater angles."
                )
                return
            }

            guard observations.count >= 10 else {
                failWith(
                    "Too few swimmer frames detected (\(observations.count)). " +
                    "Film from pool deck height at water level, side-on to the swimmer, " +
                    "with the full body visible above the waterline. " +
                    "Stay within 3–6 m of the swimmer."
                )
                return
            }

            await update(progress: 0.65, status: "Running SwimTCN model…")

            // 2 — Feature extraction: 3-second windows in the model's timebase
            let effectiveFPS = fps / Double(PoseAnalyzer.sampleRate)
            guard let tensors = FeatureExtractor.extractWindows(
                from: timedObservations, effectiveFPS: effectiveFPS
            ) else {
                failWith(
                    "Could not prepare the detected poses for analysis. " +
                    "Try re-recording with the swimmer's full body clearly visible."
                )
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
            let resultID = UUID()
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
                issueWindows: windows
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
                    issueWindows: result.issueWindows
                )
            }

            // 7 — Auto-save session (Results reads saved-state from SwiftData,
            // so a failed save is shown honestly instead of a false checkmark)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                modelContext.insert(SwimSession(result: result))
                do {
                    try modelContext.save()
                } catch {
                    AppLog.analysis.error("Session save failed: \(error.localizedDescription)")
                }
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                progress = 1.0
                // replaceTop: Back from Results must not land on this screen —
                // its .task would re-run the whole analysis and save a duplicate.
                router.replaceTop(with: .results(result))
            }

        } catch is CancellationError {
            return  // user left the screen — no failure UI, no side effects
        } catch {
            failWith(error.localizedDescription)
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
            id: UUID(),
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
            videoFileName: videoURL.lastPathComponent   // bundled demo video
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
                videoFileName: result.videoFileName
            )
        }

        guard !Task.isCancelled else { return }
        await MainActor.run {
            modelContext.insert(SwimSession(result: result))
            do {
                try modelContext.save()
            } catch {
                AppLog.analysis.error("Demo session save failed: \(error.localizedDescription)")
            }
        }

        guard !Task.isCancelled else { return }
        await MainActor.run {
            progress = 1.0
            router.replaceTop(with: .results(result))
        }
    }

    @MainActor private func update(progress p: Double, status s: String) {
        withAnimation { progress = p }
        statusText = s
    }

    private func failWith(_ message: String) {
        Task { @MainActor in
            failureMessage = message
            failed = true
        }
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
