import SwiftUI
import SwiftData
import AVKit

struct ResultsView: View {
    let result: AnalysisResult
    // Several members are internal (not private): the video/export and
    // section builders moved to ResultsView+Video.swift and
    // ResultsView+Sections.swift in the code-health split, and extensions
    // in sibling files cannot see file-private state.
    @Environment(AppRouter.self) var router
    @State var animatedScore: Double = 0
    @State private var sectionsVisible = false
    @State var player: AVPlayer? = nil
    @State var videoNaturalSize: CGSize = .zero
    @State var showSkeleton = true
    // Saved-state read from SwiftData itself — the footer never claims a save
    // that didn't happen.
    @Query var savedSessions: [SwimSession]
    @Query private var allSessions: [SwimSession]

    init(result: AnalysisResult) {
        self.result = result
        let id = result.id
        _savedSessions = Query(filter: #Predicate<SwimSession> { $0.id == id })
    }

    var isSaved: Bool { !savedSessions.isEmpty }

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

    var isNewBest: Bool {
        let prior = allSessions.filter { $0.id != result.id }.map(\.score).max()
        return TrainingLog.isNewBest(score: result.score, priorBest: prior)
    }

    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var reportImage: UIImage? = nil
    @State var shareCardImage: UIImage? = nil

    @State private var sessionToEdit: SwimSession? = nil
    @State private var celebratedBest = false

    // Export progress is deliberately NOT `@State` on this view: it ticks up to
    // 101 times per export, and state here invalidates the whole body. It lives
    // in an `@Observable` box that only `OverlayExportControl` reads — see
    // OverlayExportControl.swift. Nothing in this body reads `exportModel.state`,
    // so this view registers no dependency on it.
    @State var exportModel = OverlayExportModel()
    let videoSectionID = "session-video"

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

    func seek(to seconds: Double) {
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
                            // Row content is short; the frame extends the tap
                            // target to the HIG 44pt minimum without changing
                            // the visual weight.
                            .frame(minHeight: 44)
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
                            // Row content is short; the frame extends the tap
                            // target to the HIG 44pt minimum without changing
                            // the visual weight.
                            .frame(minHeight: 44)
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

                    // ── Full read-out ─────────────────────────────────────
                    // All ten scored faults, not just the ones that fired.
                    // Hides itself for legacy sessions (nil windows); its own
                    // bottom padding lives inside that branch so a hidden
                    // section leaves no gap.
                    FullReadoutSection(windows: result.issueWindows,
                                       issues: result.issues)
                        .staggerIn(sectionsVisible, delay: 0.21)

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
            exportModel.cancel()
        }
        .sheet(item: $sessionToEdit) { session in
            EditSessionSheet(session: session)
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
