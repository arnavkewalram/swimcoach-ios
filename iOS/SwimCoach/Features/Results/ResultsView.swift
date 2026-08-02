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

    private var isNewBest: Bool {
        let prior = allSessions.filter { $0.id != result.id }.map(\.score).max()
        return TrainingLog.isNewBest(score: result.score, priorBest: prior)
    }

    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var reportImage: UIImage? = nil

    @State private var sessionToEdit: SwimSession? = nil

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
                            HStack(spacing: 8) {
                                Image(systemName: "pencil.line")
                                    .font(.caption2)
                                    .accessibilityHidden(true)
                                if saved.name.isEmpty && saved.notes.isEmpty {
                                    Text("NAME THIS SESSION")
                                        .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                                        .tracking(1.2)
                                } else {
                                    Text(saved.name.isEmpty ? "ADD A NOTE" : saved.name)
                                        .font(.grotesk(13, .medium))
                                        .lineLimit(1)
                                    if !saved.notes.isEmpty {
                                        Text("· \(saved.notes)")
                                            .font(.caption.italic())
                                            .foregroundStyle(DS.inkTertiary)
                                            .lineLimit(1)
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
                        .padding(.bottom, 16)
                        .staggerIn(sectionsVisible, delay: 0.04)
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
                reportImage = ReportCardView.render(result: result)
            }
            if player == nil, let url = result.videoURL {
                let p = AVPlayer(url: url)
                p.isMuted = true
                player = p
                Task {
                    let asset = AVURLAsset(url: url)
                    if let track = try? await asset.loadTracks(withMediaType: .video).first,
                       let size = try? await track.load(.naturalSize) {
                        videoNaturalSize = CGSize(width: abs(size.width), height: abs(size.height))
                    }
                }
            }
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
            HStack {
                SectionHeader(title: "Session video")
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

            if let windows = result.issueWindows, !windows.isEmpty, !result.issues.isEmpty {
                IssueTimelineStrip(
                    windows: windows,
                    issues: result.issues,
                    onSelect: { time in seek(to: time) }
                )
            }
        }
        .id(videoSectionID)
    }

    private var hasSkeletonData: Bool {
        !(result.keypointFrames?.isEmpty ?? true)
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

    private var verdict: String {
        switch result.grade {
        case "A": return "Excellent technique"
        case "B": return "Good form"
        case "C": return "Room to improve"
        case "D": return "Needs work"
        default:  return "Keep practicing"
        }
    }

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

// MARK: - Issue row

private struct IssueRow: View {
    let issue: TechniqueIssue
    var canSeek: Bool = false
    var onSeeIt: () -> Void = {}
    var onDrills: () -> Void = {}
    @State private var expanded = false

    private var severityColor: Color {
        switch issue.severity {
        case .major:    return DS.severityMajor
        case .moderate: return DS.severityModerate
        case .minor:    return DS.severityMinor
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Text(issue.displayName)
                        .font(.grotesk(15, .medium))
                        .foregroundStyle(DS.ink)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    SeverityBadge(severity: issue.severity.rawValue)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(DS.inkTertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(issue.displayName), \(issue.severity.rawValue) severity")
            .accessibilityHint(expanded ? "Collapses detail" : "Shows detail and drill tip")

            if expanded {
                Rectangle().fill(DS.border).frame(height: 1)
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 12) {
                    Text(issue.description)
                        .font(.footnote)
                        .lineSpacing(3)
                        .foregroundStyle(DS.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .top, spacing: 10) {
                        Text("DRILL")
                            .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                            .tracking(1.2)
                            .foregroundStyle(DS.accent)
                            .padding(.top, 2)
                        Text(issue.tip)
                            .font(.footnote.weight(.medium))
                            .lineSpacing(3)
                            .foregroundStyle(DS.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        if canSeek {
                            Button(action: onSeeIt) {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.circle")
                                        .font(.footnote)
                                        .accessibilityHidden(true)
                                    Text("SEE IT IN YOUR VIDEO")
                                        .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                                        .tracking(1.2)
                                }
                                .foregroundStyle(DS.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(DS.accent.opacity(0.45), lineWidth: 1))
                            }
                            .accessibilityLabel("Play the video where \(issue.displayName) was strongest")
                        }

                        if !DrillCatalog.drills(fixing: issue.name).isEmpty {
                            Button(action: onDrills) {
                                HStack(spacing: 6) {
                                    Image(systemName: "figure.pool.swim")
                                        .font(.footnote)
                                        .accessibilityHidden(true)
                                    Text("DRILLS")
                                        .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                                        .tracking(1.2)
                                }
                                .foregroundStyle(DS.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(DS.accent.opacity(0.45), lineWidth: 1))
                            }
                            .accessibilityLabel("Open drills that fix \(issue.displayName)")
                        }
                    }
                }
                .padding(16)
                .transition(.opacity)
            }
        }
        .glassCard()
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                .fill(severityColor)
                .frame(width: 3)
        }
    }
}

// MARK: - Tip row

private struct TipRow: View {
    let index: Int
    let text: String
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Text(String(format: "%02d", index))
                    .font(.grotesk(15, .bold))
                    .foregroundStyle(DS.accent)
                    .padding(.top, 1)
                Text(text)
                    .font(.footnote)
                    .lineSpacing(3)
                    .foregroundStyle(DS.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(16)
            if !isLast {
                Rectangle().fill(DS.border).frame(height: 1)
                    .padding(.leading, 16)
            }
        }
    }
}
