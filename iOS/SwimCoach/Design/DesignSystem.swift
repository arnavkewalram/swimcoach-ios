import SwiftUI

// MARK: - Design Tokens

enum DS {
    // Background layers
    static let background  = Color(red: 0.04, green: 0.06, blue: 0.11)
    static let surface     = Color.white.opacity(0.065)
    static let surface2    = Color.white.opacity(0.10)
    static let border      = Color.white.opacity(0.09)
    static let borderBold  = Color.white.opacity(0.18)

    // Brand — precision teal, not generic system cyan
    static let accent      = Color(red: 0.0,  green: 0.82, blue: 0.90)
    static let accentBlue  = Color(red: 0.18, green: 0.42, blue: 0.95)
    static let accentDim   = Color(red: 0.0,  green: 0.82, blue: 0.90).opacity(0.55)

    // Semantic severity — coaching register, not error register
    static let severityMajor    = Color(red: 0.95, green: 0.35, blue: 0.35) // coral-red
    static let severityModerate = Color(red: 0.98, green: 0.65, blue: 0.18) // amber
    static let severityMinor    = Color(red: 0.55, green: 0.85, blue: 0.60) // sage-green

    // Grade palette
    static func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return Color(red: 0.25, green: 0.92, blue: 0.55)
        case "B": return accent
        case "C": return Color(red: 0.98, green: 0.78, blue: 0.20)
        case "D": return severityModerate
        default:  return severityMajor
        }
    }

    static func gradeGradient(_ grade: String) -> LinearGradient {
        let base = gradeColor(grade)
        return LinearGradient(
            colors: [base, base.opacity(0.55)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Typography helpers

extension Font {
    /// Editorial section label — ALL CAPS, tracked
    static let sectionLabel = Font.system(size: 11, weight: .semibold, design: .rounded)
    /// Stat number — large, tabular
    static let statNumber   = Font.system(size: 26, weight: .bold, design: .rounded)
    /// Stat unit (spm, /min, %)
    static let statUnit     = Font.system(size: 11, weight: .medium, design: .rounded)
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.accent)
            }
            Text(title.uppercased())
                .font(.sectionLabel)
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.55))
            Spacer()
        }
    }
}

// MARK: - Severity badge

struct SeverityBadge: View {
    let severity: String   // "major" | "moderate" | "minor"

    private var color: Color {
        switch severity.lowercased() {
        case "major":    return DS.severityMajor
        case "moderate": return DS.severityModerate
        default:         return DS.severityMinor
        }
    }

    private var dots: Int {
        switch severity.lowercased() {
        case "major":    return 3
        case "moderate": return 2
        default:         return 1
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i < dots ? color : color.opacity(0.2))
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(color.opacity(0.30), lineWidth: 1)
        )
        .clipShape(Capsule())
    }
}

// MARK: - Glassmorphism card modifier

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 16
    var borderColor: Color = DS.border

    func body(content: Content) -> some View {
        content
            .background(DS.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 16, borderColor: Color = DS.border) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, borderColor: borderColor))
    }
}

// MARK: - Thin gradient separator

struct GradientSeparator: View {
    var body: some View {
        LinearGradient(
            colors: [.clear, DS.border, .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
    }
}

// MARK: - Ambient glow (battery-conscious — 8fps is plenty for a static blob)

struct AmbientGlow: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 8.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let x1 = size.width * 0.22 + sin(t * 0.38) * size.width * 0.05
                let y1 = size.height * 0.16 + cos(t * 0.30) * size.height * 0.04
                let r1: CGFloat = size.width * 0.60
                var c1 = context
                c1.opacity = 0.13
                c1.fill(
                    Path(ellipseIn: CGRect(x: x1 - r1/2, y: y1 - r1/2, width: r1, height: r1)),
                    with: .color(DS.accent)
                )
                let x2 = size.width * 0.76 + cos(t * 0.25) * size.width * 0.05
                let y2 = size.height * 0.62 + sin(t * 0.42) * size.height * 0.04
                let r2: CGFloat = size.width * 0.52
                var c2 = context
                c2.opacity = 0.08
                c2.fill(
                    Path(ellipseIn: CGRect(x: x2 - r2/2, y: y2 - r2/2, width: r2, height: r2)),
                    with: .color(DS.accentBlue)
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .blur(radius: 72)
        .ignoresSafeArea()
    }
}

// MARK: - Animated sine waves

struct WaveShape: Shape {
    var phase: Double
    var amplitude: Double
    var frequency: Double
    var animatableData: Double { get { phase } set { phase = newValue } }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width; let h = rect.height; let mid = rect.midY
        path.move(to: CGPoint(x: 0, y: mid))
        for x in stride(from: 0, through: w, by: 1.5) {
            let y = mid + sin((x / w * frequency * .pi * 2) + phase) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.closeSubpath()
        return path
    }
}

struct AnimatedWaves: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                var w1 = WaveShape(phase: t * 0.75, amplitude: 10, frequency: 2.5)
                var p1 = w1.path(in: CGRect(x: 0, y: size.height * 0.55, width: size.width, height: size.height * 0.45))
                var c1 = context; c1.opacity = 0.07
                c1.fill(p1, with: .color(DS.accent))

                var w2 = WaveShape(phase: t * 0.50 + 1.2, amplitude: 13, frequency: 2.0)
                var p2 = w2.path(in: CGRect(x: 0, y: size.height * 0.65, width: size.width, height: size.height * 0.35))
                var c2 = context; c2.opacity = 0.05
                c2.fill(p2, with: .color(DS.accentBlue))

                var w3 = WaveShape(phase: t * 0.65 + 2.5, amplitude: 8, frequency: 3.0)
                var p3 = w3.path(in: CGRect(x: 0, y: size.height * 0.72, width: size.width, height: size.height * 0.28))
                var c3 = context; c3.opacity = 0.05
                c3.fill(p3, with: .color(DS.accentBlue.opacity(0.7)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
    }
}

// MARK: - Confetti

struct ConfettiParticle: Identifiable {
    let id = UUID()
    let x: CGFloat; let color: Color; let size: CGFloat
    let speed: Double; let angle: Double; let delay: Double
}

struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []
    @State private var animating = false
    private let colors: [Color] = [DS.accent, DS.accentBlue, .green, .yellow, .orange, .pink]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { p in
                    ConfettiPiece(particle: p, width: geo.size.width, height: geo.size.height, animating: animating)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            particles = (0..<40).map { i in
                ConfettiParticle(
                    x: CGFloat.random(in: 0.1...0.9),
                    color: colors[i % colors.count],
                    size: CGFloat.random(in: 5...9),
                    speed: Double.random(in: 1.8...3.5),
                    angle: Double.random(in: -30...30),
                    delay: Double.random(in: 0...0.6)
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { animating = true }
        }
    }
}

private struct ConfettiPiece: View {
    let particle: ConfettiParticle; let width: CGFloat; let height: CGFloat; let animating: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(particle.color)
            .frame(width: particle.size, height: particle.size * 1.6)
            .rotationEffect(.degrees(animating ? particle.angle + 360 : particle.angle))
            .offset(x: width * particle.x - width / 2, y: animating ? height + 40 : -20)
            .opacity(animating ? 0 : 1)
            .animation(.easeIn(duration: particle.speed).delay(particle.delay), value: animating)
    }
}
