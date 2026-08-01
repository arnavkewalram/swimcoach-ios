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
            AmbientGlow()
            AnimatedWaves()

            if failed {
                failureView
            } else {
                analysisView
            }
        }
        .navigationBarHidden(true)
        .task {
            if videoURL.lastPathComponent == "swim_test.mp4" {
                await runDemoAnalysis()
            } else {
                await runAnalysis()
            }
        }
    }

    // MARK: - Sub-views

    private var analysisView: some View {
        VStack(spacing: 0) {
            Spacer()

            // Title
            VStack(spacing: 6) {
                Text("ANALYZING")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(3)
                    .foregroundStyle(DS.accent.opacity(0.7))
                Text("Your Swim")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 40)

            // Progress ring
            ZStack {
                // Background track
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: 14)
                    .frame(width: 160, height: 160)

                // Progress arc — cyan → blue → purple gradient
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [DS.accent, DS.accentBlue, .purple, DS.accent],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: progress)

                // Pulsing swim icon
                PulsingIcon()
            }

            // Percentage label below ring
            Text("\(Int(progress * 100))%")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .padding(.top, 18)
                .animation(.easeInOut, value: Int(progress * 100))

            // Step indicators
            HStack(spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    StepPill(label: step, state: stepState(for: i))
                }
            }
            .padding(.top, 28)
            .padding(.horizontal, 16)

            Spacer()
            Spacer()
        }
        .padding()
    }

    private func stepState(for index: Int) -> StepState {
        if index < currentStep { return .completed }
        if index == currentStep { return .active }
        return .pending
    }

    private var failureView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 80, height: 80)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 8) {
                Text("Analysis Failed")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text(failureMessage)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            Button("Try Again") {
                failed = false
                Task { await runAnalysis() }
            }
            .font(.headline)
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [DS.accent, DS.accentBlue],
                               startPoint: .leading, endPoint: .trailing)
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding()
    }

    // MARK: - Pipeline

    private func runAnalysis() async {
        do {
            // 1 — Pose extraction (0 → 60%)
            let (observations, fps, sampledFrames) = try await PoseAnalyzer.analyze(videoURL: videoURL) { p in
                Task { @MainActor in
                    self.progress = p * 0.60
                    self.statusText = "Extracting pose keypoints… \(Int(p * 100))%"
                }
            }

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
                from: observations, effectiveFPS: effectiveFPS
            ) else {
                failWith(
                    "Could not prepare the detected poses for analysis. " +
                    "Try re-recording with the swimmer's full body clearly visible."
                )
                return
            }

            // 3 — SwimTCN inference (the ML model is the only detection path),
            // probabilities averaged across windows
            var probSum = [Float](repeating: 0, count: SwimTCNRunner.expectedLabelCount)
            for tensor in tensors {
                let p = try SwimTCNRunner.shared.predict(tensor: tensor)
                for i in probSum.indices { probSum[i] += p[i] }
            }
            let probs = probSum.map { $0 / Float(tensors.count) }
            let issues = FeedbackEngine.decode(probabilities: probs)
            await update(progress: 0.80, status: "Decoding technique issues…")

            await update(progress: 0.85, status: "Computing stroke metrics…")

            // 4 — Motion metrics
            let metrics = BiomechanicsEngine().metrics(
                from: observations, fps: fps, sampleRate: PoseAnalyzer.sampleRate,
                sampledFrames: sampledFrames
            )

            await update(progress: 0.92, status: "Building report…")

            // 5 — Assemble result
            let score = BiomechanicsEngine.score(from: issues)
            let grade = BiomechanicsEngine.grade(from: score)
            let sortedIssues = issues.sorted { $0.severity > $1.severity }

            var result = AnalysisResult(
                id: UUID(),
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
                analyzedAt: Date()
            )

            // 6 — AI coaching tips (Claude Haiku)
            await update(progress: 0.98, status: "Generating coaching tips…")
            let aiTips = await CoachingService.generateTips(for: result)
            if !aiTips.isEmpty {
                result = AnalysisResult(
                    id: result.id, score: result.score, grade: result.grade,
                    strokeCount: result.strokeCount, kickRatePerMin: result.kickRatePerMin,
                    strokeAsymmetry: result.strokeAsymmetry, frameCount: result.frameCount,
                    sampledFrames: result.sampledFrames,
                    fps: result.fps, issues: result.issues, tips: aiTips,
                    analyzedAt: result.analyzedAt
                )
            }

            // 7 — Auto-save session
            await MainActor.run {
                modelContext.insert(SwimSession(result: result))
                try? modelContext.save()
            }

            await MainActor.run {
                progress = 1.0
                router.push(.results(result))
            }

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
            analyzedAt: Date()
        )

        // Step 3 — real Claude tips call
        await update(progress: 0.98, status: "Generating coaching tips…")
        let aiTips = await CoachingService.generateTips(for: result)
        if !aiTips.isEmpty {
            result = AnalysisResult(
                id: result.id, score: result.score, grade: result.grade,
                strokeCount: result.strokeCount, kickRatePerMin: result.kickRatePerMin,
                strokeAsymmetry: result.strokeAsymmetry, frameCount: result.frameCount,
                sampledFrames: result.sampledFrames,
                fps: result.fps, issues: result.issues, tips: aiTips,
                analyzedAt: result.analyzedAt
            )
        }

        await MainActor.run {
            modelContext.insert(SwimSession(result: result))
            try? modelContext.save()
        }

        await MainActor.run {
            progress = 1.0
            router.push(.results(result))
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

// MARK: - Pulsing swim icon

private struct PulsingIcon: View {
    @State private var pulse = false

    var body: some View {
        Image(systemName: "figure.pool.swim")
            .font(.system(size: 32))
            .foregroundStyle(DS.accent)
            .scaleEffect(pulse ? 1.08 : 0.95)
            .opacity(pulse ? 1.0 : 0.75)
            .animation(
                .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                value: pulse
            )
            .onAppear { pulse = true }
    }
}

// MARK: - Step states & pill

enum StepState { case completed, active, pending }

private struct StepPill: View {
    let label: String
    let state: StepState

    @State private var glowing = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(dotBackground)
                    .frame(width: 10, height: 10)
                if state == .active {
                    Circle()
                        .fill(DS.accent.opacity(glowing ? 0.4 : 0.1))
                        .frame(width: 18, height: 18)
                        .animation(
                            .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                            value: glowing
                        )
                        .onAppear { glowing = true }
                }
            }
            Text(label)
                .font(.system(size: 9, weight: state == .active ? .semibold : .regular))
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var dotBackground: Color {
        switch state {
        case .completed: return DS.accent
        case .active:    return DS.accent
        case .pending:   return Color.white.opacity(0.15)
        }
    }

    private var labelColor: Color {
        switch state {
        case .completed: return DS.accent
        case .active:    return .white
        case .pending:   return .secondary
        }
    }
}
