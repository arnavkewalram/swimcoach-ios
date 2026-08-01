import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            DS.background.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    WelcomePage().tag(0)
                    CameraPage().tag(1)
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
    }
}

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            PageIcon(name: "figure.pool.swim")
            Spacer().frame(height: 32)
            Text("SwimCoach")
                .font(.statNumber)
                .foregroundStyle(.white)
            Spacer().frame(height: 16)
            Text("AI Swim Coach in your pocket")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer().frame(height: 14)
            Text("Upload a side-on poolside video and get detailed biomechanics feedback in seconds.")
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            CTAButton(label: "Get Started") {}
        }
    }
}

private struct CameraPage: View {
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
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer().frame(height: 32)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(tips, id: \.self) { tip in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DS.accent)
                        Text(tip)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 48)
            Spacer()
            CTAButton(label: "Next") {}
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
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 10)
            .background(DS.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.border, lineWidth: 1))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
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
