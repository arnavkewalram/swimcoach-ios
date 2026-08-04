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
    /// Secondary step. Dark keeps the chalk @62% derivation raised in
    /// v1.40.2 (5.9–6.2:1 on slate); light was still the original ink @62%,
    /// which composites to only 4.82:1 on paper — passing AA but sitting
    /// under the ≥5:1 bar dark was deliberately held to, i.e. the parity gap
    /// ran the wrong way. Light deepens to @68% → 5.88:1 on paper /
    /// 6.10:1 on white stock, matching dark step for step.
    static let inkSecondary = Color(
        light: UIColor(red: 0.066, green: 0.098, blue: 0.137, alpha: 0.68),  // ink @ 68%
        dark:  UIColor(red: 0.886, green: 0.914, blue: 0.941, alpha: 0.62))  // ink @ 62%
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
    //
    // The light ramp is set at a MATCHED INK WEIGHT: every light severity
    // value lands in a 4.64–4.76:1 band on the paper ground, so severity is
    // carried by hue alone and no step reads heavier than its neighbours.
    // The four print hues are unchanged (brick 5°, ochre 38°, pine 143°,
    // grade-D orange 25°) — only value moved down. Rationale:
    //   • Small tracked text — SeverityBadge (9pt), "ANALYSIS FAILED"
    //     (11pt), grade chips (13pt) — needs 4.5:1. The old ochre managed
    //     only 2.67:1 on paper against 9.48:1 for its dark twin, and pine
    //     (3.91), grade-D (3.44) and brick (4.44) also missed the bar.
    //   • Grade chips invert to `onAccent` white ON these fills when
    //     selected; the band clears 4.5:1 in that direction too
    //     (white-on-ochre was 2.91:1).
    //   • The same tokens tint non-text marks (34pt warning glyph, focus
    //     bars, score arc) which only need 3:1 — the band clears that with
    //     room, so no separate text-tier token is warranted.
    static let severityMajor = Color(
        light: UIColor(red: 0.756, green: 0.252, blue: 0.204, alpha: 1),  // brick red #C14034
        dark:  UIColor(red: 0.937, green: 0.502, blue: 0.443, alpha: 1))  // coral brick #EF8071
    static let severityModerate = Color(
        light: UIColor(red: 0.600, green: 0.384, blue: 0.024, alpha: 1),  // ochre #996206
        dark:  UIColor(red: 0.929, green: 0.702, blue: 0.302, alpha: 1))  // amber #EDB34D
    static let severityMinor = Color(
        light: UIColor(red: 0.219, green: 0.483, blue: 0.321, alpha: 1),  // pine green #387B52
        dark:  UIColor(red: 0.451, green: 0.784, blue: 0.588, alpha: 1))  // spearmint #73C896

    /// Grade-D orange sits between C's ochre and F's brick.
    private static let gradeD = Color(
        light: UIColor(red: 0.675, green: 0.343, blue: 0.108, alpha: 1),  // #AC571C
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

/// Primary action — the ONE primary treatment in the app.
///
/// The meet-sheet hero: solid lane-blue, label set left on the grid, and a
/// single affordance parked in the far trailing slot. No gradient, no glow.
/// Home, Review and Onboarding each hand-rolled this inline before it lived
/// here; every primary CTA now renders through this type, so the tier moves
/// in one place.
///
/// `icon` defaults to `arrow.right` because a primary action almost always
/// moves the user forward. Pass a different symbol where the action names
/// itself rather than pointing onward (`AnalyzingView`'s recovery buttons),
/// or `nil` for a bare label.
struct PrimaryButtonLabel: View {
    let title: String
    var icon: String? = "arrow.right"

    var body: some View {
        HStack {
            Text(title)
                .font(.grotesk(18, .medium))
            Spacer()
            if let icon {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(DS.onAccent)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .background(DS.accent)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
