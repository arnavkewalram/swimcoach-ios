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

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if currentPage < 2 {
                        Button("Skip") { hasSeenOnboarding = true }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DS.inkSecondary)
                            .padding(.horizontal, 24)
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
                    .fill(i == current ? DS.accent : DS.border)
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
            PrimaryButtonLabel(title: label)
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }
}

private struct PageKicker: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.sectionLabel)
            .tracking(2.0)
            .foregroundStyle(DS.accent)
    }
}

private struct WelcomePage: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "figure.pool.swim")
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(DS.accent)
                .accessibilityHidden(true)
            Spacer().frame(height: 28)
            PageKicker(text: "SwimCoach")
            Spacer().frame(height: 12)
            Text("An AI swim coach\nin your pocket")
                .font(.grotesk(30, .bold))
                .foregroundStyle(DS.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer().frame(height: 14)
            Text("Film a swim from the pool deck — or import one from Photos — and get detailed biomechanics feedback in seconds. No account, all on device.")
                .font(.subheadline)
                .lineSpacing(3)
                .foregroundStyle(DS.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
            Spacer()
            CTAButton(label: "Get started", action: onNext)
        }
    }
}

private struct CameraPage: View {
    let onNext: () -> Void

    private let tips = [
        "Stable phone — watch the level line",
        "3–6 metres from the swimmer",
        "Bright lighting preferred"
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "video")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(DS.accent)
                .accessibilityHidden(true)
            Spacer().frame(height: 28)
            PageKicker(text: "Setup")
            Spacer().frame(height: 12)
            Text("Film from the side")
                .font(.grotesk(30, .bold))
                .foregroundStyle(DS.ink)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 14)
            Text("Stand at the pool edge and film the full lane, with the swimmer's entire body visible from head to feet.")
                .font(.subheadline)
                .lineSpacing(3)
                .foregroundStyle(DS.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
            Spacer().frame(height: 28)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(tips.enumerated()), id: \.offset) { i, tip in
                    HStack(spacing: 12) {
                        Text(String(format: "%02d", i + 1))
                            .font(.grotesk(13, .bold))
                            .foregroundStyle(DS.accent)
                        Text(tip)
                            .font(.subheadline)
                            .foregroundStyle(DS.ink)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    if i < tips.count - 1 {
                        Rectangle().fill(DS.border).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .glassCard()
            .padding(.horizontal, 40)
            Spacer()
            CTAButton(label: "Next", action: onNext)
        }
    }
}

private struct ResultsPage: View {
    let onFinish: () -> Void

    private struct ResultCard: View {
        let index: String
        let title: String
        let description: String

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(index)
                    .font(.grotesk(13, .bold))
                    .foregroundStyle(DS.accent)
                Text(title)
                    .font(.grotesk(14, .medium))
                    .foregroundStyle(DS.ink)
                Text(description)
                    .font(.caption)
                    .lineSpacing(2)
                    .foregroundStyle(DS.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassCard()
            .accessibilityElement(children: .combine)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            PageKicker(text: "Every session")
            Spacer().frame(height: 12)
            Text("What you'll get")
                .font(.grotesk(30, .bold))
                .foregroundStyle(DS.ink)
            Spacer().frame(height: 32)
            VStack(spacing: 10) {
                ResultCard(index: "01", title: "Technique score",
                           description: "A 0–100 biomechanics score with a letter grade")
                ResultCard(index: "02", title: "Faults, on your video",
                           description: "Named stroke faults with severity — and a skeleton overlay showing exactly when they happened")
                ResultCard(index: "03", title: "Drills & progress",
                           description: "A drill library mapped to every fault, plus trends, weekly goals, and a focus to work on")
            }
            .padding(.horizontal, 40)
            Spacer()
            CTAButton(label: "Start analyzing", action: onFinish)
        }
    }
}
