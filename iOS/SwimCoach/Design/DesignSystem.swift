import SwiftUI

// MARK: - Design Tokens
//
// Direction: "meet sheet" sports-science editorial, in two appearances.
//
// Light — the original meet sheet: warm paper ground, ink navy text, a
// single saturated lane-blue for action/data, print-register severity
// colors. Flat surfaces with hairline rules — no blur, no glow,
// no gradients. Space Grotesk carries display/data; SF carries body text.
//
// Dark — "Night Meet": the same sheet read on a pool deck after sunset.
// Wet-slate charcoal-blue ground (never pure black), chalk-white ink with
// the identical tonal hierarchy steps, hairlines that read as pale
// chlorine-blue lane lines, the lane-blue accent tuned brighter for dark
// contrast, and severity colors lifted into the same hue families at
// dark-legible luminance.
//
// Every token below resolves per-trait via UIColor dynamic providers, so
// call sites are appearance-agnostic and this file stays the single
// source of truth for both palettes.

private extension Color {
    /// Adaptive token: resolves per the current appearance.
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

enum DS {
    // Ground + ink
    /// Warm paper / wet-slate deck.
    static let background = Color(
        light: UIColor(red: 0.969, green: 0.961, blue: 0.937, alpha: 1),  // #F7F5EF
        dark:  UIColor(red: 0.071, green: 0.094, blue: 0.125, alpha: 1))  // #121820
    /// Cards: white stock / raised slate.
    static let surface = Color(
        light: .white,
        dark:  UIColor(red: 0.106, green: 0.133, blue: 0.169, alpha: 1))  // #1B222B
    /// Recessed fields: ink wash on paper / chalk wash on slate.
    static let surface2 = Color(
        light: UIColor(red: 0.066, green: 0.098, blue: 0.137, alpha: 0.05),
        dark:  UIColor(red: 0.863, green: 0.906, blue: 0.941, alpha: 0.07))
    /// Ink navy / chalk white. Secondary and tertiary steps derive by
    /// opacity so the tonal hierarchy is identical in both appearances.
    static let ink = Color(
        light: UIColor(red: 0.066, green: 0.098, blue: 0.137, alpha: 1),  // #111923
        dark:  UIColor(red: 0.886, green: 0.914, blue: 0.941, alpha: 1))  // #E2E9F0
    static let inkSecondary = DS.ink.opacity(0.62)
    /// Tertiary stays an opacity derivation of `ink`, but the dark step is
    /// raised: chalk @40% composites to ~3.3:1 on the slate ground (fails
    /// AA at caption sizes); @58% it holds ≥5:1 on both ground and surface.
    /// Light keeps the original 40% paper derivation.
    static let inkTertiary = Color(
        light: UIColor(red: 0.066, green: 0.098, blue: 0.137, alpha: 0.40),  // ink @ 40%
        dark:  UIColor(red: 0.886, green: 0.914, blue: 0.941, alpha: 0.58))  // ink @ 58%
    /// Hairlines: ink rules on paper / pale chlorine-blue lane lines on slate.
    static let border = Color(
        light: UIColor(red: 0.066, green: 0.098, blue: 0.137, alpha: 0.14),
        dark:  UIColor(red: 0.612, green: 0.784, blue: 0.882, alpha: 0.21)) // #9CC8E1
    static let borderBold = Color(
        light: UIColor(red: 0.066, green: 0.098, blue: 0.137, alpha: 0.32),
        dark:  UIColor(red: 0.612, green: 0.784, blue: 0.882, alpha: 0.42))
    /// Muted data mark (empty-week dashes and other zero-state ticks):
    /// identical to `border` in light, but a half step brighter in dark —
    /// these encode data, not rules, and must not sink into the lane-line
    /// hairlines on slate.
    static let markMuted = Color(
        light: UIColor(red: 0.066, green: 0.098, blue: 0.137, alpha: 0.14),
        dark:  UIColor(red: 0.612, green: 0.784, blue: 0.882, alpha: 0.30))
    /// Modal sheet ground: paper in light (a sheet is just another page of
    /// the meet packet), raised slate in dark so sheets separate from the
    /// #121820 backdrop behind them instead of sampling identically.
    static let sheetSurface = Color(
        light: UIColor(red: 0.969, green: 0.961, blue: 0.937, alpha: 1),  // = background
        dark:  UIColor(red: 0.106, green: 0.133, blue: 0.169, alpha: 1))  // = surface #1B222B

    // Lane blue — the one accent. Used for actions and live data, never decoration.
    static let accent = Color(
        light: UIColor(red: 0.043, green: 0.322, blue: 0.863, alpha: 1),  // #0B52DC
        dark:  UIColor(red: 0.290, green: 0.565, blue: 1.000, alpha: 1))  // #4A90FF
    /// Text/icons sitting ON an accent fill (primary buttons, chips):
    /// white on the deep light-mode blue; slate on the bright dark-mode
    /// blue, where white would fall under contrast.
    static let onAccent = Color(
        light: .white,
        dark:  UIColor(red: 0.043, green: 0.071, blue: 0.106, alpha: 1))  // #0B121B

    // Severity — print register, not alarm register. Same hue families in
    // dark, lifted to hold contrast on the slate ground.
    static let severityMajor = Color(
        light: UIColor(red: 0.788, green: 0.263, blue: 0.212, alpha: 1),  // brick red
        dark:  UIColor(red: 0.937, green: 0.502, blue: 0.443, alpha: 1))  // coral brick #EF8071
    static let severityModerate = Color(
        light: UIColor(red: 0.800, green: 0.541, blue: 0.078, alpha: 1),  // ochre
        dark:  UIColor(red: 0.929, green: 0.702, blue: 0.302, alpha: 1))  // amber #EDB34D
    static let severityMinor = Color(
        light: UIColor(red: 0.243, green: 0.537, blue: 0.357, alpha: 1),  // pine green
        dark:  UIColor(red: 0.451, green: 0.784, blue: 0.588, alpha: 1))  // spearmint #73C896

    /// Grade-D orange sits between C's ochre and F's brick.
    private static let gradeD = Color(
        light: UIColor(red: 0.804, green: 0.408, blue: 0.129, alpha: 1),
        dark:  UIColor(red: 0.925, green: 0.596, blue: 0.322, alpha: 1))  // #EC9852

    static func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return severityMinor
        case "B": return accent
        case "C": return severityModerate
        case "D": return gradeD
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
    /// Set this inside the horizontal branch of a `ViewThatFits` row: the
    /// title then refuses to wrap, so a row that can't hold it on one line
    /// genuinely fails to fit and the stacked fallback engages instead of
    /// the label fracturing mid-word. The lane rule stays greedy either
    /// way, so it still absorbs the slack when the row does fit.
    var singleLine: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.sectionLabel)
                .tracking(1.6)
                .foregroundStyle(DS.inkSecondary)
                .fixedSize(horizontal: singleLine, vertical: false)
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
        .foregroundStyle(DS.onAccent)
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
