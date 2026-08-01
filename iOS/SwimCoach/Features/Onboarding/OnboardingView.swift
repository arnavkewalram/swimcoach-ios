import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @State private var currentPage = 0

    private func advance() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            currentPage += 1
        }
    }

    var body: some View {
        ZStack {
            DS.background.ignoresSafeArea()
            AmbientGlow()
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                // Skip — always available before the last page
                HStack {
                    Spacer()
                    if currentPage < 2 {
                        Button("Skip") { hasSeenOnboarding = true }
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                    }
                }
                .frame(height: 44)

                TabView(selection: $currentPage) {
                    WelcomePage(onNext: advance).tag(0)
                    CameraPage(onNext: advance).tag(1)
                    ResultsPage(onFinish: { hasSeenOnboarding = true }).tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                PageDots(current: currentPage, total: 3)
                    .padding(.bottom, 48)
            }
        }
    }
}

private struct PageDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current ? DS.accent : Color.white.opacity(0.25))
                    .frame(width: i == current ? 20 : 6, height: 6)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: current)
            }
        }
        .padding(.top, 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(total)")
    }
}

private struct CTAButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(colors: [DS.accent, DS.accentBlue], startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: DS.accent.opacity(0.35), radius: 20, x: 0, y: 8)
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }
}

private struct PageIcon: View {
    let name: String

    var body: some View {
        ZStack {
            Circle()
                .fill(DS.accent.opacity(0.12))
                .frame(width: 108, height: 108)
            Image(systemName: name)
                .font(.system(size: 70))
                .foregroundStyle(DS.accent)
        }
        .accessibilityHidden(true)
    }
}

private struct WelcomePage: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            PageIcon(name: "figure.pool.swim")
            Spacer().frame(height: 32)
            Text("SWIMCOACH")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(3)
                .foregroundStyle(DS.accent.opacity(0.8))
            Spacer().frame(height: 12)
            Text("An AI swim coach\nin your pocket")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer().frame(height: 14)
            Text("Upload a side-on poolside video and get detailed biomechanics feedback in seconds.")
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            CTAButton(label: "Get Started", action: onNext)
        }
    }
}

private struct CameraPage: View {
    let onNext: () -> Void

    private let tips = [
        "Stable phone, waist height",
        "2–5 metres from the swimmer",
        "Bright lighting preferred"
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            PageIcon(name: "video.badge.checkmark")
            Spacer().frame(height: 32)
            Text("Film from the side")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer().frame(height: 14)
            Text("Stand at the pool edge, film the full lane. Make sure your entire body is visible from head to feet.")
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer().frame(height: 32)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(tips, id: \.self) { tip in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DS.accent)
                            .accessibilityHidden(true)
                        Text(tip)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 48)
            Spacer()
            CTAButton(label: "Next", action: onNext)
        }
    }
}

private struct ResultsPage: View {
    let onFinish: () -> Void

    private struct ResultCard: View {
        let icon: String
        let title: String
        let description: String

        var body: some View {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundStyle(DS.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 10)
            .background(DS.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.border, lineWidth: 1))
            .accessibilityElement(children: .combine)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            PageIcon(name: "chart.bar.doc.horizontal")
            Spacer().frame(height: 32)
            Text("What you'll get")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer().frame(height: 36)
            HStack(spacing: 12) {
                ResultCard(icon: "chart.bar.fill", title: "Technique Score", description: "0–100 biomechanics score")
                ResultCard(icon: "exclamationmark.triangle.fill", title: "Issues Detected", description: "Named faults with severity")
                ResultCard(icon: "lightbulb.fill", title: "Drill Tips", description: "Specific exercises to fix each fault")
            }
            .padding(.horizontal, 24)
            Spacer()
            CTAButton(label: "Start Analyzing", action: onFinish)
        }
    }
}
