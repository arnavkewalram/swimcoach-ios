import SwiftUI
import SwiftData
import AVKit

struct ResultsView: View {
    let result: AnalysisResult
    @Environment(AppRouter.self) private var router
    @State private var animatedScore: Double = 0
    @State private var sectionsVisible = false
    @State private var player: AVPlayer? = nil
    @State private var videoNaturalSize: CGSize = .zero
    @State private var showSkeleton = true
    // Saved-state read from SwiftData itself — the footer never claims a save
    // that didn't happen.
    @Query private var savedSessions: [SwimSession]
    @Query private var allSessions: [SwimSession]

    init(result: AnalysisResult) {
        self.result = result
        let id = result.id
        _savedSessions = Query(filter: #Predicate<SwimSession> { $0.id == id })
    }

    private var isSaved: Bool { !savedSessions.isEmpty }

    /// Chronological recent scores for the report sparkline, ending with
    /// this session (appended manually when it isn't in the store yet).
    private var reportTrendScores: [Int]? {
        var scores = TrainingLog.recentScores(
            from: allSessions.map { TrainingLog.Entry(date: $0.analyzedAt, score: $0.score) })
        if savedSessions.isEmpty { scores = Array((scores + [result.score]).suffix(10)) }
        return scores.count >= 2 ? scores : nil
    }

    /// The chronologically previous saved session, decoded — compare target.
    private var previousResult: AnalysisResult? {
        allSessions
            .filter { $0.id != result.id && $0.analyzedAt < result.analyzedAt }
            .max(by: { $0.analyzedAt < $1.analyzedAt })?
            .decoded()
    }

    private var isNewBest: Bool {
        let prior = allSessions.filter { $0.id != result.id }.map(\.score).max()
        return TrainingLog.isNewBest(score: result.score, priorBest: prior)
    }

    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var reportImage: UIImage? = nil
    @State private var shareCardImage: UIImage? = nil

    @State private var sessionToEdit: SwimSession? = nil
    @State private var celebratedBest = false

    enum VideoExportState: Equatable {
        case idle, exporting(Double), ready(URL), failed
    }
    @State private var exportState: VideoExportState = .idle
    @State private var exportTask: Task<Void, Never>? = nil
    private let videoSectionID = "session-video"

    private var canSeekIssues: Bool {
        result.videoURL != nil && !(result.issueWindows?.isEmpty ?? true)
    }

    /// Jump the video to where this issue's window probability peaked.
    private func seekToPeak(of issue: TechniqueIssue) {
        guard let windows = result.issueWindows,
              let index = FeedbackEngine.labelIndex(of: issue.name),
              let peak = windows.peakWindow(labelIndex: index) else { return }
        seek(to: peak.start)
    }

    private func seek(to seconds: Double) {
        withAnimation { scrollProxy?.scrollTo(videoSectionID, anchor: .top) }
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
        player?.play()
    }

    var body: some View {
        ZStack {
            DS.background.ignoresSafeArea()

            ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Score panel ────────────────────────────────────────
                    scorePanel
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                        .staggerIn(sectionsVisible, delay: 0)

                    // ── Session label (saved sessions only) ───────────────
                    if let saved = savedSessions.first {
                        Button {
                            sessionToEdit = saved
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "pencil.line")
                                    .font(.caption2)
                                    .accessibilityHidden(true)
                                if saved.name.isEmpty && saved.notes.isEmpty {
                                    Text("NAME THIS SESSION")
                                        .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                                        .tracking(1.2)
                                } else {
                                    // Name row up top; the note gets its own
                                    // line so it can wrap instead of truncating.
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            if !saved.swimmer.isEmpty {
                                                Text(saved.swimmer.uppercased())
                                                    .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                                                    .tracking(1.0)
                                                    .foregroundStyle(DS.accent)
                                                    .fixedSize()
                                            }
                                            Text(saved.name.isEmpty ? "ADD A NOTE" : saved.name)
                                                .font(.grotesk(13, .medium))
                                                .lineLimit(1)
                                        }
                                        if !saved.notes.isEmpty {
                                            Text(saved.notes)
                                                .font(.caption.italic())
                                                .foregroundStyle(DS.inkTertiary)
                                                .lineLimit(2)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                                Spacer()
                            }
                            .foregroundStyle(saved.name.isEmpty && saved.notes.isEmpty
                                             ? DS.accent : DS.inkSecondary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(saved.name.isEmpty
                                            ? "Name this session"
                                            : "Session name: \(saved.name). Edit name and notes.")
                        .padding(.bottom, 10)
                        .staggerIn(sectionsVisible, delay: 0.04)
                    }

                    // ── Compare to previous (saved sessions with history) ──
                    if isSaved, let previous = previousResult {
                        Button {
                            router.push(.compare(earlier: previous, later: result))
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.caption2.weight(.semibold))
                                    .accessibilityHidden(true)
                                Text("COMPARE TO PREVIOUS SESSION")
                                    .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                                    .tracking(1.2)
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.caption2.weight(.semibold))
                                    .accessibilityHidden(true)
                            }
                            .foregroundStyle(DS.accent)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) { Rectangle().fill(DS.border).frame(height: 1) }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Compare this session to the previous one")
                        .padding(.bottom, 16)
                        .staggerIn(sectionsVisible, delay: 0.06)
                    }

                    // ── Quality notes ─────────────────────────────────────
                    if result.sampledFrames > 0 && result.detectionRate < 0.20 {
                        qualityNote(
                            icon: "eye.trianglebadge.exclamationmark",
                            color: DS.severityModerate,
                            text: "Low detection quality — results may be less accurate. Film closer to the swimmer from pool deck level."
                        )
                        .padding(.bottom, 10)
                        .staggerIn(sectionsVisible, delay: 0.08)
                    }
                    if result.strokeCount < 4 {
                        qualityNote(
                            icon: "exclamationmark.triangle",
                            color: DS.severityModerate,
                            text: "Stroke count may be inaccurate — ensure the full body was visible."
                        )
                        .padding(.bottom, 10)
                        .staggerIn(sectionsVisible, delay: 0.08)
                    }

                    // ── Session video ─────────────────────────────────────
                    if let url = result.videoURL {
                        videoSection(url: url)
                            .padding(.bottom, 20)
                            .staggerIn(sectionsVisible, delay: 0.10)
                    }

                    // ── Metrics ───────────────────────────────────────────
                    metricsStrip
                        .padding(.bottom, 28)
                        .staggerIn(sectionsVisible, delay: 0.12)

                    // ── Issues ────────────────────────────────────────────
                    if !result.issues.isEmpty {
                        SectionHeader(title: "Issues detected")
                            .padding(.bottom, 12)
                            .staggerIn(sectionsVisible, delay: 0.18)
                        VStack(spacing: 8) {
                            ForEach(result.issues, id: \.name) { issue in
                                IssueRow(issue: issue,
                                         canSeek: canSeekIssues,
                                         onSeeIt: { seekToPeak(of: issue) },
                                         onDrills: { router.push(.drills(highlightIssue: issue.name)) })
                            }
                        }
                        .padding(.bottom, 28)
                        .staggerIn(sectionsVisible, delay: 0.18)
                    }

                    // ── Tips ──────────────────────────────────────────────
                    if !result.tips.isEmpty {
                        SectionHeader(title: "Coaching tips")
                            .padding(.bottom, 12)
                            .staggerIn(sectionsVisible, delay: 0.24)
                        VStack(spacing: 0) {
                            ForEach(Array(result.tips.enumerated()), id: \.offset) { i, tip in
                                TipRow(index: i + 1, text: tip,
                                       isLast: i == result.tips.count - 1)
                            }
                        }
                        .glassCard()
                        .padding(.bottom, 28)
                        .staggerIn(sectionsVisible, delay: 0.24)
                    }

                    // ── Footer ────────────────────────────────────────────
                    footer
                        .padding(.bottom, 40)
                        .staggerIn(sectionsVisible, delay: 0.30)
                }
                .padding(.horizontal, 24)
            }
            .onAppear { self.scrollProxy = scrollProxy }
            }
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Results")
                    .font(.grotesk(17, .medium))
                    .foregroundStyle(DS.ink)
            }
        }
        .toolbarBackground(DS.background, for: .navigationBar)
        .toolbar {
            if let reportImage {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: Image(uiImage: reportImage),
                        preview: SharePreview("SwimCoach report — \(result.score)/100",
                                              image: Image(uiImage: reportImage))
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(DS.accent)
                    }
                    .accessibilityLabel("Share report card")
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) { animatedScore = Double(result.score) }
            sectionsVisible = true
            if reportImage == nil {
                if isNewBest && !celebratedBest {
                    celebratedBest = true
                    Haptics.success()
                }
                reportImage = ReportCardView.render(
                    result: result, trendScores: reportTrendScores, newBest: isNewBest)
            }
            if shareCardImage == nil {
                // Deferred off the appearance frame so first paint isn't
                // blocked by a second ImageRenderer pass stacked on the
                // score animations. ImageRenderer must stay on the main
                // actor; the SHARE CARD control appears once this lands.
                let model = shareCardModel
                Task(priority: .utility) { @MainActor in
                    guard shareCardImage == nil else { return }
                    shareCardImage = ShareCardView.render(model: model)
                }
            }
            if player == nil, let url = result.videoURL {
                let p = AVPlayer(url: url)
                p.isMuted = true
                player = p
                Task {
                    let asset = AVURLAsset(url: url)
                    if let track = try? await asset.loadTracks(withMediaType: .video).first,
                       let size = try? await track.load(.naturalSize),
                       let transform = try? await track.load(.preferredTransform) {
                        videoNaturalSize = VideoTransform.displaySize(natural: size, transform: transform)
                    }
                }
            }
        }
        // The pencil button edits the saved session's name/swimmer in place —
        // re-render the cached card whenever an edit changes what the card
        // would show (ShareCardModel is Equatable over exactly those inputs).
        .onChange(of: shareCardModel) { _, model in
            shareCardImage = ShareCardView.render(model: model)
        }
        .onDisappear {
            player?.pause()
            exportTask?.cancel()
        }
        .sheet(item: $sessionToEdit) { session in
            EditSessionSheet(session: session)
        }
    }

    // MARK: - Session video

    private func videoSection(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // At accessibility type sizes the header row can't fit beside
            // the controls — fall to a vertical stack instead of letting
            // the label break mid-word.
            ViewThatFits(in: .horizontal) {
                HStack {
                    SectionHeader(title: videoSectionTitle)
                    videoControls
                }
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: videoSectionTitle)
                    HStack { videoControls }
                }
            }
            ZStack {
                if let player {
                    VideoPlayer(player: player)
                    if showSkeleton, let frames = result.keypointFrames, !frames.isEmpty {
                        SkeletonOverlayView(player: player, frames: frames,
                                            videoSize: videoNaturalSize)
                    }
                } else {
                    Color.black
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.border, lineWidth: 1))
            .accessibilityLabel("Analyzed swim video with detected joint overlay. Review your stroke alongside the feedback below.")

            // Hides itself for legacy sessions (nil windows/duration).
            IssueTimelineStrip(
                windows: result.issueWindows,
                issues: result.issues,
                durationSeconds: result.durationSeconds,
                onSeek: { time in seek(to: time) }
            )
        }
        .id(videoSectionID)
    }

    private var hasSkeletonData: Bool {
        !(result.keypointFrames?.isEmpty ?? true)
    }

    private var videoSectionTitle: String {
        result.durationText.map { "Video · \($0)" } ?? "Session video"
    }

    @ViewBuilder
    private var videoControls: some View {
        shareCardControl
        if hasSkeletonData {
            Button {
                showSkeleton.toggle()
            } label: {
                Text(showSkeleton ? "HIDE JOINTS" : "SHOW JOINTS")
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                    .tracking(1.2)
                    .foregroundStyle(showSkeleton ? DS.accent : DS.inkTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(showSkeleton ? DS.accent.opacity(0.5) : DS.border, lineWidth: 1))
            }
            .accessibilityLabel(showSkeleton ? "Hide detected joints overlay" : "Show detected joints overlay")

            exportControl
        }
    }

    /// The formatted content of the square social card — swimmer/name come
    /// from the saved session when there is one.
    private var shareCardModel: ShareCardModel {
        let saved = savedSessions.first
        return ShareCardModel(result: result,
                              swimmer: saved?.swimmer ?? "",
                              sessionName: saved?.name ?? "")
    }

    /// Share the square session summary card — sits with the video export
    /// controls and shares their compact bordered style.
    @ViewBuilder
    private var shareCardControl: some View {
        if let shareCardImage {
            ShareLink(
                item: Image(uiImage: shareCardImage),
                preview: SharePreview(shareCardModel.previewTitle,
                                      image: Image(uiImage: shareCardImage))
            ) {
                Text("SHARE CARD")
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                    .tracking(1.2)
                    .foregroundStyle(DS.inkSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(DS.border, lineWidth: 1))
            }
            .accessibilityLabel("Share session summary card")
        }
    }

    @ViewBuilder
    private var exportControl: some View {
        switch exportState {
        case .idle, .failed:
            Button {
                startExport()
            } label: {
                Text(exportState == .failed ? "RETRY EXPORT" : "EXPORT")
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                    .tracking(1.2)
                    .foregroundStyle(DS.inkSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(DS.border, lineWidth: 1))
            }
            .accessibilityLabel("Export video with skeleton overlay")
        case .exporting(let p):
            Text("\(Int(p * 100))%")
                .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                .tracking(1.2)
                .foregroundStyle(DS.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(DS.accent.opacity(0.4), lineWidth: 1))
                .accessibilityLabel("Exporting video, \(Int(p * 100)) percent")
        case .ready(let url):
            ShareLink(item: url) {
                Text("SHARE VIDEO")
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                    .tracking(1.2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(DS.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .accessibilityLabel("Share exported video")
        }
    }

    private func startExport() {
        guard let url = result.videoURL, let frames = result.keypointFrames else { return }
        exportState = .exporting(0)
        exportTask = Task {
            do {
                let out = try await OverlayVideoExporter.export(videoURL: url, frames: frames) { p in
                    Task { @MainActor in
                        if case .exporting = exportState { exportState = .exporting(p) }
                    }
                }
                await MainActor.run { exportState = .ready(out) }
            } catch is CancellationError {
                await MainActor.run { exportState = .idle }
            } catch {
                AppLog.storage.error("Overlay export failed: \(error.localizedDescription)")
                await MainActor.run { exportState = .failed }
            }
        }
    }

    // MARK: - Score panel

    private var gradeColor: Color { DS.gradeColor(result.grade) }

    private var verdict: String { ShareCardModel.verdict(for: result.grade) }

    private var scorePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TECHNIQUE SCORE")
                .font(.sectionLabel)
                .tracking(1.6)
                .foregroundStyle(DS.inkTertiary)
                .padding(.bottom, 6)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(Int(animatedScore))")
                    .font(.grotesk(84, .bold))
                    .foregroundStyle(DS.ink)
                    .contentTransition(.numericText())
                Text(result.grade)
                    .font(.grotesk(32, .bold))
                    .foregroundStyle(gradeColor)
                Spacer()
            }
            .padding(.bottom, 10)

            // Score rule — flat 0–100 bar in the grade color
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(DS.border)
                    Rectangle()
                        .fill(gradeColor)
                        .frame(width: geo.size.width * animatedScore / 100)
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
            .padding(.bottom, 12)

            HStack {
                Text(verdict.uppercased())
                    .font(.grotesk(13, .medium))
                    .tracking(1.8)
                    .foregroundStyle(gradeColor)
                Spacer()
                if isNewBest {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.to.line")
                            .font(.system(size: 9, weight: .semibold))
                            .accessibilityHidden(true)
                        Text("NEW BEST")
                            .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                            .tracking(1.4)
                    }
                    .foregroundStyle(DS.severityMinor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(DS.severityMinor.opacity(0.55), lineWidth: 1))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Technique score \(result.score) out of 100, grade \(result.grade). \(verdict)." +
                            (isNewBest ? " New personal best." : ""))
    }

    // MARK: - Quality note

    private func qualityNote(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(color)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .lineSpacing(2)
                .foregroundStyle(DS.inkSecondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle().fill(color.opacity(0.7)).frame(width: 3)
        }
        .background(color.opacity(0.05))
    }

    // MARK: - Metrics

    private var metricsStrip: some View {
        HStack(spacing: 0) {
            metric(value: result.strokeCount > 0 ? "\(result.strokeCount)" : "–",
                   label: "STROKES")
            metricDivider
            if let spm = result.strokeRatePerMin {
                metric(value: String(format: "%.0f", spm), label: "STROKES/MIN")
                metricDivider
            }
            metric(value: result.kickRatePerMin > 0 ? String(format: "%.0f", result.kickRatePerMin) : "–",
                   label: "KICKS/MIN")
            metricDivider
            metric(value: result.strokeCount > 0 ? String(format: "%.0f%%", result.strokeAsymmetry * 100) : "–",
                   label: "ASYMMETRY",
                   valueColor: result.strokeAsymmetry > 0.3 ? DS.severityModerate : DS.ink)
        }
        .padding(.vertical, 8)
    }

    private var metricDivider: some View {
        Rectangle().fill(DS.border).frame(width: 1, height: 40)
    }

    private func metric(value: String, label: String, valueColor: Color = DS.ink) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.grotesk(24, .bold))
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
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

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: isSaved ? "checkmark" : "exclamationmark.triangle")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSaved ? DS.severityMinor : DS.severityModerate)
                    .accessibilityHidden(true)
                Text(isSaved
                     ? "Session saved"
                     : "Session not saved — a storage error occurred")
                    .font(.footnote)
                    .foregroundStyle(isSaved ? DS.inkSecondary : DS.severityModerate)
            }
            .frame(maxWidth: .infinity)

            Button {
                router.popToRoot()
            } label: {
                SecondaryButtonLabel(title: "Done")
            }
            .buttonStyle(ScaleButtonStyle())
        }
    }
}

// MARK: - Stagger modifier (no-op under Reduce Motion)

private struct StaggerIn: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let visible: Bool
    let delay: Double

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .opacity(visible ? 1 : 0)
                .offset(y: visible ? 0 : 8)
                .animation(.easeOut(duration: 0.4).delay(delay), value: visible)
        }
    }
}

private extension View {
    func staggerIn(_ visible: Bool, delay: Double) -> some View {
        modifier(StaggerIn(visible: visible, delay: delay))
    }
}
