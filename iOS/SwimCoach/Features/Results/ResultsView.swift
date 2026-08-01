import SwiftUI
import SwiftData

struct ResultsView: View {
    let result: AnalysisResult
    @Environment(AppRouter.self) private var router
    @State private var animatedScore: Double = 0
    @State private var showConfetti = false
    @State private var sectionsVisible = false

    var body: some View {
        ZStack(alignment: .top) {
            DS.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {

                    // ── Score ring ─────────────────────────────────────────
                    scoreRing
                        .padding(.top, 20)
                        .padding(.bottom, 16)
                        .staggerIn(sectionsVisible, delay: 0)

                    // ── Grade banner ───────────────────────────────────────
                    gradeBanner
                        .padding(.bottom, 6)
                        .staggerIn(sectionsVisible, delay: 0.1)

                    // ── Summary ────────────────────────────────────────────
                    Text(result.summary)
                        .font(.system(size: 14))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.white.opacity(0.62))
                        .padding(.horizontal, 32)
                        .padding(.bottom, 28)
                        .staggerIn(sectionsVisible, delay: 0.15)

                    // ── Detection quality warning ──────────────────────────
                    if result.sampledFrames > 0 && result.detectionRate < 0.20 {
                        HStack(spacing: 6) {
                            Image(systemName: "eye.trianglebadge.exclamationmark")
                                .foregroundStyle(DS.severityMinor)
                                .font(.system(size: 12))
                            Text("Low detection quality — results may be less accurate. Film closer to the swimmer from pool deck level.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.65))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(DS.severityMinor.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.severityMinor.opacity(0.25), lineWidth: 1))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        .staggerIn(sectionsVisible, delay: 0.20)
                    }

                    // ── Stroke confidence warning ──────────────────────────
                    if result.strokeCount < 4 {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(DS.severityModerate)
                                .font(.system(size: 12))
                            Text("Stroke count may be inaccurate — ensure full body was visible")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.65))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(DS.severityModerate.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.severityModerate.opacity(0.3), lineWidth: 1))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        .staggerIn(sectionsVisible, delay: 0.20)
                    }

                    // ── Stats strip ────────────────────────────────────────
                    statsStrip
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                        .staggerIn(sectionsVisible, delay: 0.25)

                    // ── Issues ─────────────────────────────────────────────
                    if !result.issues.isEmpty {
                        issuesSection
                            .padding(.bottom, 28)
                            .staggerIn(sectionsVisible, delay: 0.30)
                    }

                    // ── Tips ───────────────────────────────────────────────
                    if !result.tips.isEmpty {
                        tipsSection
                            .padding(.bottom, 32)
                            .staggerIn(sectionsVisible, delay: 0.35)
                    }

                    // ── Footer ─────────────────────────────────────────────
                    resultFooter
                        .padding(.bottom, 44)
                        .staggerIn(sectionsVisible, delay: 0.40)
                }
            }

            if showConfetti {
                ConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .background(DS.background.ignoresSafeArea())
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4)) { animatedScore = Double(result.score) }
            sectionsVisible = true
            if result.score >= 85 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showConfetti = true }
            }
        }
    }

    // MARK: - Score ring

    private var scoreRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.04), lineWidth: 2)
                .frame(width: 220, height: 220)

            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 16)
                .frame(width: 200, height: 200)

            Circle()
                .trim(from: 0, to: animatedScore / 100)
                .stroke(scoreGradient, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1.4), value: animatedScore)

            if result.grade == "A" || result.grade == "B" {
                RingParticles(color: DS.gradeColor(result.grade))
                    .frame(width: 224, height: 224)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 2) {
                Text("\(Int(animatedScore))")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 1.4), value: animatedScore)
                Text("GRADE \(result.grade)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(gradeColor)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Technique score \(result.score) out of 100, grade \(result.grade)")
    }

    // MARK: - Grade banner

    private var gradeBanner: some View {
        Text(gradeBannerText)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .tracking(2.0)
            .foregroundStyle(gradeColor)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(gradeColor.opacity(0.12))
                    .overlay(Capsule().stroke(gradeColor.opacity(0.35), lineWidth: 1))
            )
    }

    private var gradeBannerText: String {
        switch result.grade {
        case "A": return "EXCELLENT TECHNIQUE"
        case "B": return "GOOD FORM"
        case "C": return "ROOM TO IMPROVE"
        case "D": return "NEEDS WORK"
        default:  return "KEEP PRACTICING"
        }
    }

    // MARK: - Stats strip (editorial — no icon circles)

    private var statsStrip: some View {
        HStack(spacing: 0) {
            ResultStat(
                value: result.strokeCount > 0 ? "\(result.strokeCount)" : "–",
                label: "STROKES",
                color: DS.accent
            )
            statDivider
            ResultStat(
                value: result.kickRatePerMin > 0 ? String(format: "%.0f", result.kickRatePerMin) : "–",
                label: "KICKS / MIN",
                color: DS.accentBlue
            )
            statDivider
            ResultStat(
                value: result.strokeCount > 0 ? String(format: "%.0f%%", result.strokeAsymmetry * 100) : "–",
                label: "ASYMMETRY",
                color: result.strokeAsymmetry > 0.3 ? DS.severityModerate : DS.severityMinor
            )
        }
        .padding(.vertical, 18)
        .background(DS.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DS.border, lineWidth: 1)
        )
    }

    private var statDivider: some View {
        Rectangle()
            .fill(DS.border)
            .frame(width: 1, height: 36)
    }

    // MARK: - Issues section

    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Issues Detected")
                .padding(.horizontal, 20)

            GradientSeparator()
                .padding(.horizontal, 20)
                .padding(.bottom, 4)

            ForEach(result.issues, id: \.name) { issue in
                IssueCard(issue: issue)
                    .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Coaching tips

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Coaching Tips")
                .padding(.horizontal, 20)

            GradientSeparator()
                .padding(.horizontal, 20)
                .padding(.bottom, 4)

            ForEach(Array(result.tips.enumerated()), id: \.offset) { i, tip in
                TipCard(index: i + 1, text: tip)
                    .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Footer

    private var resultFooter: some View {
        VStack(spacing: 16) {
            GradientSeparator()
                .padding(.horizontal, 20)

            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DS.severityMinor)
                    .font(.system(size: 14))
                Text("Session saved")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
            }

            Button {
                router.popToRoot()
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(DS.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(DS.accent.opacity(0.25), lineWidth: 1)
                    )
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Helpers

    private var scoreGradient: LinearGradient {
        let c = gradeColor
        return LinearGradient(
            colors: [c, c.opacity(0.65)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var gradeColor: Color { DS.gradeColor(result.grade) }
}

// MARK: - Stagger modifier

private extension View {
    func staggerIn(_ visible: Bool, delay: Double) -> some View {
        self
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 10)
            .animation(.easeOut(duration: 0.45).delay(delay), value: visible)
    }
}

// MARK: - Ring particles

private struct RingParticles: View {
    let color: Color
    @State private var appeared = false

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .offset(y: -112)
                    .rotationEffect(.degrees(Double(i) * 45.0))
                    .opacity(appeared ? 0.65 : 0)
                    .animation(
                        .easeOut(duration: 0.6).delay(Double(i) * 0.06 + 0.8),
                        value: appeared
                    )
            }
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Stat display (no icon, editorial numbers)

private struct ResultStat: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.statNumber)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.statUnit)
                .tracking(0.8)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Issue card

private struct IssueCard: View {
    let issue: TechniqueIssue
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header row
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    // Severity dot column
                    SeverityBadge(severity: issue.severity.rawValue)

                    Text(issue.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(issue.displayName), \(issue.severity.rawValue) severity")
            .accessibilityHint(expanded ? "Collapses detail" : "Shows detail and drill tip")

            // Expanded detail
            if expanded {
                Rectangle()
                    .fill(DS.border)
                    .frame(height: 1)
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 12) {
                    Text(issue.description)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)

                    // Drill tip
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "figure.pool.swim")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.accent)
                            .frame(width: 16)
                        Text(issue.tip)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(DS.accent.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(DS.accent.opacity(0.18), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(DS.surface2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(DS.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.border, lineWidth: 1))
        // Left severity accent — 5pt, fully opaque
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(severityColor)
                .frame(width: 4)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 14, bottomLeadingRadius: 14,
                    bottomTrailingRadius: 0, topTrailingRadius: 0
                ))
        }
    }

    private var severityColor: Color {
        switch issue.severity {
        case .major:    return DS.severityMajor
        case .moderate: return DS.severityModerate
        case .minor:    return DS.severityMinor
        }
    }
}

// MARK: - Coaching tip card (editorial)

private struct TipCard: View {
    let index: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Bold index number — tabular, no circle
            Text("\(index)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(DS.accent)
                .frame(width: 28, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 0) {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.border, lineWidth: 1))
        // Teal left accent bar
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DS.accentDim)
                .frame(width: 3)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 12, bottomLeadingRadius: 12,
                    bottomTrailingRadius: 0, topTrailingRadius: 0
                ))
        }
    }
}
