import SwiftUI
import SwiftData
import AVKit

struct ResultsView: View {
    let result: AnalysisResult
    @Environment(AppRouter.self) private var router
    @State private var animatedScore: Double = 0
    @State private var sectionsVisible = false
    @State private var player: AVPlayer? = nil
    // Saved-state read from SwiftData itself — the footer never claims a save
    // that didn't happen.
    @Query private var savedSessions: [SwimSession]

    init(result: AnalysisResult) {
        self.result = result
        let id = result.id
        _savedSessions = Query(filter: #Predicate<SwimSession> { $0.id == id })
    }

    private var isSaved: Bool { !savedSessions.isEmpty }

    var body: some View {
        ZStack {
            DS.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Score panel ────────────────────────────────────────
                    scorePanel
                        .padding(.top, 16)
                        .padding(.bottom, 20)
                        .staggerIn(sectionsVisible, delay: 0)

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
                                IssueRow(issue: issue)
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
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DS.background, for: .navigationBar)
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) { animatedScore = Double(result.score) }
            sectionsVisible = true
            if player == nil, let url = result.videoURL {
                let p = AVPlayer(url: url)
                p.isMuted = true
                player = p
            }
        }
        .onDisappear {
            player?.pause()
        }
    }

    // MARK: - Session video

    private func videoSection(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Session video")
            Group {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    Color.black
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.border, lineWidth: 1))
            .accessibilityLabel("Analyzed swim video. Review your stroke alongside the feedback below.")
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

            Text(verdict.uppercased())
                .font(.grotesk(13, .medium))
                .tracking(1.8)
                .foregroundStyle(gradeColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Technique score \(result.score) out of 100, grade \(result.grade). \(verdict).")
    }

    // MARK: - Quality note

    private func qualityNote(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 13))
                .lineSpacing(2)
                .foregroundStyle(DS.inkSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.45), lineWidth: 1))
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
        .padding(.vertical, 16)
        .glassCard()
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
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: isSaved ? "checkmark" : "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSaved ? DS.severityMinor : DS.severityModerate)
                    .accessibilityHidden(true)
                Text(isSaved
                     ? "Session saved"
                     : "Session not saved — a storage error occurred")
                    .font(.system(size: 13))
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

// MARK: - Stagger modifier

private extension View {
    func staggerIn(_ visible: Bool, delay: Double) -> some View {
        self
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 8)
            .animation(.easeOut(duration: 0.4).delay(delay), value: visible)
    }
}

// MARK: - Issue row

private struct IssueRow: View {
    let issue: TechniqueIssue
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
                        .font(.system(size: 11, weight: .medium))
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
                        .font(.system(size: 13))
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
                            .font(.system(size: 13, weight: .medium))
                            .lineSpacing(3)
                            .foregroundStyle(DS.ink)
                            .fixedSize(horizontal: false, vertical: true)
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
                    .font(.system(size: 14))
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
