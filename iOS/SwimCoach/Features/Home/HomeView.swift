import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \SwimSession.analyzedAt, order: .reverse) private var sessions: [SwimSession]
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    #if DEBUG
    @State private var showFilePicker = false
    @State private var docsVideoURL: URL? = nil
    #endif
    @State private var shimmerPhase: CGFloat = -1.0
    @State private var headerAppeared = false

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 12 { return "Good morning, Coach" }
        if h < 17 { return "Good afternoon, Coach" }
        return "Good evening, Coach"
    }

    var body: some View {
        ZStack {
            DS.background.ignoresSafeArea()
            AmbientGlow()

            ScrollView {
                VStack(spacing: 28) {
                    // Header — editorial lockup
                    VStack(spacing: 0) {
                        // Greeting chip
                        Text(greeting.uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .tracking(2.0)
                            .foregroundStyle(DS.accent.opacity(0.7))
                            .padding(.bottom, 14)
                            .opacity(headerAppeared ? 1 : 0)
                            .offset(y: headerAppeared ? 0 : -4)
                            .animation(.easeOut(duration: 0.45).delay(0.1), value: headerAppeared)

                        // Icon + wordmark — compact horizontal
                        HStack(alignment: .center, spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(DS.accent.opacity(0.12))
                                    .frame(width: 48, height: 48)
                                Image(systemName: "figure.pool.swim")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(DS.accent)
                            }
                            .shadow(color: DS.accent.opacity(0.4), radius: 12, x: 0, y: 0)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("SwimCoach")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("AI Technique Analysis")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.38))
                            }
                        }
                        .opacity(headerAppeared ? 1 : 0)
                        .offset(y: headerAppeared ? 0 : 6)
                        .animation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.05), value: headerAppeared)
                    }
                    .padding(.top, 24)

                    // Last session card
                    if let last = sessions.first {
                        LastSessionCard(
                            session: last,
                            previousSession: sessions.count > 1 ? sessions[1] : nil
                        ) {
                            if let result = last.decoded() {
                                router.push(.results(result))
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Stats strip
                    if !sessions.isEmpty {
                        StatsStrip(sessions: sessions)
                    }

                    // Primary CTA
                    Button {
                        router.push(.camera)
                    } label: {
                        ZStack {
                            Label("Analyze Swim", systemImage: "video.fill")
                                .font(.title3.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .foregroundStyle(.white)

                            // Shimmer overlay
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                .white.opacity(0),
                                                .white.opacity(0.22),
                                                .white.opacity(0)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * 0.4)
                                    .offset(x: shimmerPhase * geo.size.width * 1.4)
                                    .clipped()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .allowsHitTesting(false)
                        }
                        .background(
                            LinearGradient(
                                colors: [DS.accent, DS.accentBlue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: DS.accent.opacity(0.35), radius: 16, x: 0, y: 6)
                    }
                    .buttonStyle(ScaleButtonStyle())

                    // History
                    if !sessions.isEmpty {
                        Button {
                            router.push(.history)
                        } label: {
                            Label("View History (\(sessions.count))", systemImage: "clock.arrow.circlepath")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(DS.surface)
                                .foregroundStyle(.white.opacity(0.85))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(DS.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }

                    // Debug
                    #if DEBUG
                    VStack(spacing: 8) {
                        Text("DEV TOOLS")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.25))
                        VStack(spacing: 8) {
                            HStack(spacing: 12) {
                                Button {
                                    if let url = Bundle.main.url(forResource: "swim_test", withExtension: "mp4") {
                                        router.push(.analyzing(url))
                                    } else {
                                        router.push(.results(AnalysisResult.demo))
                                    }
                                } label: {
                                    Label("Demo", systemImage: "sparkles")
                                        .font(.subheadline.bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.purple.opacity(0.18))
                                        .foregroundStyle(.purple.opacity(0.8))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                                        )
                                }

                                Button {
                                    showFilePicker = true
                                } label: {
                                    Label("Load Video", systemImage: "folder.badge.plus")
                                        .font(.subheadline.bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.orange.opacity(0.15))
                                        .foregroundStyle(.orange.opacity(0.8))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                        )
                                }
                            }
                            if let mp4 = docsVideoURL {
                                Button {
                                    router.push(.analyzing(mp4))
                                } label: {
                                    Label("Docs: \(mp4.lastPathComponent)", systemImage: "play.circle.fill")
                                        .font(.subheadline.bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.green.opacity(0.15))
                                        .foregroundStyle(.green.opacity(0.85))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .opacity(0.5)
                    }
                    .fileImporter(
                        isPresented: $showFilePicker,
                        allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
                        allowsMultipleSelection: false
                    ) { result in
                        if case .success(let urls) = result, let url = urls.first {
                            let accessed = url.startAccessingSecurityScopedResource()
                            let tmp = FileManager.default.temporaryDirectory
                                .appendingPathComponent(url.lastPathComponent)
                            try? FileManager.default.copyItem(at: url, to: tmp)
                            if accessed { url.stopAccessingSecurityScopedResource() }
                            router.push(.analyzing(tmp))
                        }
                    }
                    #endif

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
        }
        .fullScreenCover(isPresented: .constant(!hasSeenOnboarding)) { OnboardingView() }
        .navigationBarHidden(true)
        .onAppear {
            headerAppeared = true
            withAnimation(.easeInOut(duration: 1.1).delay(0.35)) {
                shimmerPhase = 1.4
            }
            #if DEBUG
            if let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
               let found = try? FileManager.default.contentsOfDirectory(at: docsDir, includingPropertiesForKeys: nil)
                   .first(where: { $0.pathExtension.lowercased() == "mp4" }) {
                docsVideoURL = found
            }
            #endif
        }
    }
}

// MARK: - Stats Strip

private struct StatsStrip: View {
    let sessions: [SwimSession]

    private var bestScore: Int { sessions.map(\.score).max() ?? 0 }
    private var avgScore: Int {
        guard !sessions.isEmpty else { return 0 }
        return sessions.map(\.score).reduce(0, +) / sessions.count
    }

    var body: some View {
        HStack(spacing: 0) {
            MicroStat(value: "\(sessions.count)", label: "sessions", icon: "list.bullet")
            Divider().frame(height: 28).background(DS.border)
            MicroStat(value: "\(bestScore)", label: "best", icon: "star.fill")
            Divider().frame(height: 28).background(DS.border)
            MicroStat(value: "\(avgScore)", label: "avg", icon: "chart.bar.fill")
        }
        .padding(.vertical, 10)
        .background(DS.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.border, lineWidth: 1)
        )
    }
}

private struct MicroStat: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(DS.accent.opacity(0.7))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Last Session Card

private struct LastSessionCard: View {
    let session: SwimSession
    let previousSession: SwimSession?
    let onTap: () -> Void

    private var gradeColor: Color { DS.gradeColor(session.grade) }

    private var delta: Int? {
        guard let prev = previousSession else { return nil }
        return session.score - prev.score
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // Left accent border
                Rectangle()
                    .fill(gradeColor)
                    .frame(width: 4)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 16,
                            bottomLeadingRadius: 16,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0
                        )
                    )

                VStack(alignment: .leading, spacing: 12) {
                    // Header row
                    HStack {
                        Text("LAST SESSION")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.4))
                        Spacer()
                        Text(session.analyzedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Score + details
                    HStack(alignment: .center, spacing: 16) {
                        // Mini score ring
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 5)
                                .frame(width: 44, height: 44)
                            Circle()
                                .trim(from: 0, to: CGFloat(session.score) / 100)
                                .stroke(gradeColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .frame(width: 44, height: 44)
                                .rotationEffect(.degrees(-90))
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(session.score)")
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)

                                // Grade badge
                                Text(session.grade)
                                    .font(.system(size: 13, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(gradeColor.opacity(0.22))
                                    .foregroundStyle(gradeColor)
                                    .clipShape(Capsule())

                                // Delta badge
                                if let d = delta {
                                    Text(d >= 0 ? "+\(d)" : "\(d)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(d >= 0 ? .green : .orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background((d >= 0 ? Color.green : Color.orange).opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }

                            HStack(spacing: 10) {
                                Label("\(session.issueCount) issue\(session.issueCount == 1 ? "" : "s")",
                                      systemImage: "exclamationmark.circle")
                                Label("\(session.strokeCount) strokes",
                                      systemImage: "arrow.left.arrow.right")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(16)
            }
            .background(DS.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(gradeColor.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: gradeColor.opacity(0.08), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Scale button style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
