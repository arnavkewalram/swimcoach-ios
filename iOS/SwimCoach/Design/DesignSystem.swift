import SwiftUI

// MARK: - Design Tokens
//
// Direction: "meet sheet" sports-science editorial. Warm paper ground, ink
// navy text, a single saturated lane-blue for action/data, print-register
// severity colors. Flat surfaces with hairline rules — no blur, no glow,
// no gradients. Space Grotesk carries display/data; SF carries body text.

enum DS {
    // Ground + ink
    static let background = Color(red: 0.969, green: 0.961, blue: 0.937) // warm paper
    static let surface    = Color.white                                   // cards
    static let surface2   = Color(red: 0.066, green: 0.098, blue: 0.137).opacity(0.05) // recessed fields
    static let ink        = Color(red: 0.066, green: 0.098, blue: 0.137) // #111923
    static let inkSecondary = DS.ink.opacity(0.62)
    static let inkTertiary  = DS.ink.opacity(0.40)
    static let border     = DS.ink.opacity(0.14)   // hairlines
    static let borderBold = DS.ink.opacity(0.32)

    // Lane blue — the one accent. Used for actions and live data, never decoration.
    static let accent     = Color(red: 0.043, green: 0.322, blue: 0.863) // #0B52DC
    static let accentDim  = accent.opacity(0.55)
    // Kept for API compatibility; maps to ink in the editorial system.
    static let accentBlue = ink

    // Severity — print register, not alarm register
    static let severityMajor    = Color(red: 0.788, green: 0.263, blue: 0.212) // brick red
    static let severityModerate = Color(red: 0.800, green: 0.541, blue: 0.078) // ochre
    static let severityMinor    = Color(red: 0.243, green: 0.537, blue: 0.357) // pine green

    static func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return severityMinor
        case "B": return accent
        case "C": return severityModerate
        case "D": return Color(red: 0.804, green: 0.408, blue: 0.129)
        default:  return severityMajor
        }
    }
}

// MARK: - Typography

extension Font {
    /// Display numerals & wordmarks — Space Grotesk, scaling with Dynamic
    /// Type relative to a text style inferred from the base size.
    static func grotesk(_ size: CGFloat, _ weight: GroteskWeight = .bold) -> Font {
        .custom(weight.postScriptName, size: size, relativeTo: Self.styleFor(size))
    }

    private static func styleFor(_ size: CGFloat) -> TextStyle {
        switch size {
        case 30...: return .largeTitle
        case 20..<30: return .title2
        case 15..<20: return .body
        case 12..<15: return .footnote
        default: return .caption2
        }
    }

    /// Editorial section label — ALL CAPS, tracked (use with .tracking(1.4))
    static let sectionLabel = Font.custom(GroteskWeight.medium.postScriptName, size: 11, relativeTo: .caption2)
    /// Stat number
    static let statNumber   = Font.custom(GroteskWeight.bold.postScriptName, size: 26, relativeTo: .title2)
    /// Stat unit (spm, /min, %)
    static let statUnit     = Font.custom(GroteskWeight.medium.postScriptName, size: 11, relativeTo: .caption2)
}

enum GroteskWeight {
    case regular, medium, bold
    var postScriptName: String {
        switch self {
        case .regular: return "SpaceGrotesk-Regular"
        case .medium:  return "SpaceGrotesk-Medium"
        case .bold:    return "SpaceGrotesk-Bold"
        }
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.sectionLabel)
                .tracking(1.6)
                .foregroundStyle(DS.inkSecondary)
            LaneRule()
        }
    }
}

// MARK: - Lane rule (double hairline — the pool-lane motif)

struct LaneRule: View {
    var body: some View {
        VStack(spacing: 3) {
            Rectangle().fill(DS.border).frame(height: 1)
            Rectangle().fill(DS.border).frame(height: 1)
        }
        .accessibilityHidden(true)
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

    var body: some View {
        Text(severity.uppercased())
            .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
            .tracking(1.2)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(0.55), lineWidth: 1))
    }
}

// MARK: - Flat editorial card (name kept for API compatibility)

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 12
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
    func glassCard(cornerRadius: CGFloat = 12, borderColor: Color = DS.border) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, borderColor: borderColor))
    }
}

// MARK: - Separator (name kept for API compatibility — now a hairline)

struct GradientSeparator: View {
    var body: some View {
        Rectangle().fill(DS.border).frame(height: 1)
    }
}

// MARK: - Retired atmosphere layers (stubs keep untouched screens compiling
// while each is restyled; the editorial system has no ambient decoration)

struct AmbientGlow: View {
    var body: some View { EmptyView() }
}

struct AnimatedWaves: View {
    var body: some View { EmptyView() }
}

struct ConfettiView: View {
    var body: some View { EmptyView() }
}

// MARK: - Score arc (flat editorial gauge — thin stroke, no glow)

struct ScoreArc: View {
    let score: Int
    let color: Color
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.10, to: 0.90)
                .stroke(DS.border, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(90))
            Circle()
                .trim(from: 0.10, to: 0.10 + 0.80 * Double(max(0, min(100, score))) / 100.0)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(90))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Buttons

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// Primary action: solid lane-blue, grotesk label. No gradient, no glow.
struct PrimaryButtonLabel: View {
    let title: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.callout.weight(.semibold))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.grotesk(17, .medium))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(DS.accent)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Secondary action: paper button with hairline.
struct SecondaryButtonLabel: View {
    let title: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline.weight(.medium))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.grotesk(16, .medium))
        }
        .foregroundStyle(DS.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(DS.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.borderBold, lineWidth: 1))
    }
}
