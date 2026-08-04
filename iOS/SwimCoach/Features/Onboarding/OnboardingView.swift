import SwiftUI

// MARK: - Onboarding
//
// The intro is set as three pages of a meet program — EVENT 01–03 —
// on the same leading 24pt grid as Home's masthead. Each page opens
// with a tracked kicker + heat counter over a LaneRule, exactly the
// register Home prints its greeting/date row in. The shell owns one
// hero CTA (Home's "Analyze a swim" button, verbatim) plus lane-tick
// page markers and a micro-label Skip, so the composition stays
// anchored while pages slide. The pages live in OnboardingPages.swift.

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @State private var currentPage = 0

    #if DEBUG
    /// `-onboardingPage <0-2>` opens the intro on a given page so
    /// simulator screenshot runs can reach pages 2–3 without taps.
    init() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-onboardingPage"), i + 1 < args.count,
           let page = Int(args[i + 1]), (0...2).contains(page) {
            _currentPage = State(initialValue: page)
        }
    }
    #endif

    private func advance() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            currentPage += 1
        }
    }

    private func finish() {
        hasSeenOnboarding = true
    }

    private var ctaTitle: String {
        switch currentPage {
        case 0:  return "Get started"
        case 1:  return "Next"
        default: return "Start analyzing"
        }
    }

    var body: some View {
        ZStack {
            DS.background.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    WelcomePage().tag(0)
                    CameraPage().tag(1)
                    ResultsPage().tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                footer
            }
        }
    }

    // Anchored footer: hero CTA on the grid, lane-tick page markers
    // leading, Skip as a micro-label in the trailing slot.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if currentPage < 2 { advance() } else { finish() }
            } label: {
                HStack {
                    Text(ctaTitle)
                        .font(.grotesk(18, .medium))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.body.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(DS.onAccent)
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(DS.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(ScaleButtonStyle())

            HStack {
                PageTicks(current: currentPage, total: 3)
                Spacer()
                if currentPage < 2 {
                    Button(action: finish) {
                        Text("SKIP INTRO")
                            .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                            .tracking(1.4)
                            .foregroundStyle(DS.inkTertiary)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip the intro")
                }
            }
            .frame(height: 36)
            .padding(.top, 6)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

// MARK: - Page markers (lane ticks, not iOS dots)

private struct PageTicks: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Rectangle()
                    .fill(i == current ? DS.accent : DS.borderBold)
                    .frame(width: i == current ? 22 : 10, height: 3)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: current)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(total)")
    }
}
