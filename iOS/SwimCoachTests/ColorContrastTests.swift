import XCTest
import SwiftUI
import UIKit
@testable import SwimCoach

/// WCAG 2.1 contrast guard for the semantic tokens in `DS`.
///
/// Every token is resolved for BOTH appearances through
/// `UIColor(...).resolvedColor(with:)`, so this measures the pixels each
/// appearance actually paints rather than whatever a comment claims. Tokens
/// declared with an alpha (the ink tiers) are composited onto their ground
/// first, exactly as CoreAnimation does.
///
/// Thresholds follow WCAG 2.1 §1.4.3 / §1.4.11:
///   • 4.5:1 — small text (< 18pt regular / < 14pt bold). Nearly all text in
///     this app is small: SeverityBadge is 9pt, `sectionLabel` 11pt, grade
///     chips 13pt.
///   • 3.0:1 — non-text marks: the 34pt warning glyph, focus bars, score arc.
///   • 5.0:1 — the house bar for the ink hierarchy, held on both appearances
///     so neither light nor dark is the weaker one for the same tier.
final class ColorContrastTests: XCTestCase {

    // MARK: - Cases

    /// A token, the ground(s) it is painted on, and the ratio it must clear.
    private struct ContrastCase {
        let token: String
        let color: Color
        let grounds: [Ground]
        let required: Double
    }

    private struct Ground {
        let name: String
        let color: Color
    }

    private var paperOrSlate: Ground { Ground(name: "DS.background", color: DS.background) }
    private var stockOrRaised: Ground { Ground(name: "DS.surface", color: DS.surface) }

    /// Small-text tier: 4.5:1 on every ground the token is painted on.
    private var textCases: [ContrastCase] {
        [
            .init(token: "DS.ink", color: DS.ink,
                  grounds: [paperOrSlate, stockOrRaised], required: 4.5),
            // Ink hierarchy is held to the house 5:1 bar in BOTH appearances.
            // All three tiers carry text — tertiary sets unfinished-take
            // dates, scrubber timecodes, waiting counts and retention lines —
            // so none of them gets a decorative exemption.
            .init(token: "DS.inkSecondary", color: DS.inkSecondary,
                  grounds: [paperOrSlate, stockOrRaised], required: 5.0),
            .init(token: "DS.inkTertiary", color: DS.inkTertiary,
                  grounds: [paperOrSlate, stockOrRaised], required: 5.0),
            .init(token: "DS.accent", color: DS.accent,
                  grounds: [paperOrSlate, stockOrRaised], required: 4.5),
            // Severity ramp: tints SeverityBadge (9pt), "ANALYSIS FAILED"
            // (11pt), issue rows and delta readouts.
            .init(token: "DS.severityMajor", color: DS.severityMajor,
                  grounds: [paperOrSlate, stockOrRaised], required: 4.5),
            .init(token: "DS.severityModerate", color: DS.severityModerate,
                  grounds: [paperOrSlate, stockOrRaised], required: 4.5),
            .init(token: "DS.severityMinor", color: DS.severityMinor,
                  grounds: [paperOrSlate, stockOrRaised], required: 4.5),
        ]
        // Grade letters: 13pt bold chips + the big grade glyph. "D" is the
        // only route to the private gradeD token, so drive them all.
        + ["A", "B", "C", "D", "F"].map {
            ContrastCase(token: "DS.gradeColor(\"\($0)\")", color: DS.gradeColor($0),
                         grounds: [paperOrSlate, stockOrRaised], required: 4.5)
        }
    }

    // MARK: - Tests

    func testSemanticTextTokensClearAAInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for testCase in textCases {
                for ground in testCase.grounds {
                    assertContrast(testCase.color, on: ground, style: style,
                                   atLeast: testCase.required, token: testCase.token)
                }
            }
        }
    }

    /// Selected grade chips and primary buttons invert: `onAccent` is painted
    /// ON the fill. That direction has to clear 4.5:1 too.
    func testInkOnFilledChipsClearsAA() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            assertContrast(DS.onAccent, on: Ground(name: "DS.accent", color: DS.accent),
                           style: style, atLeast: 4.5, token: "DS.onAccent")
            for grade in ["A", "B", "C", "D", "F"] {
                assertContrast(DS.onAccent,
                               on: Ground(name: "DS.gradeColor(\"\(grade)\")", color: DS.gradeColor(grade)),
                               style: style, atLeast: 4.5, token: "DS.onAccent")
            }
        }
    }

    /// The severity tokens double as non-text marks (34pt warning glyph,
    /// focus bars, score arc), which only need 3:1 per §1.4.11. Pinned so a
    /// future "make the charts lighter" tweak can't drop them below the
    /// graphical floor even if a text-tier split is introduced later.
    func testSeverityMarksClearGraphicalFloor() {
        let marks = [("DS.severityMajor", DS.severityMajor),
                     ("DS.severityModerate", DS.severityModerate),
                     ("DS.severityMinor", DS.severityMinor),
                     ("DS.gradeColor(\"D\")", DS.gradeColor("D"))]
        for style in [UIUserInterfaceStyle.light, .dark] {
            for (name, color) in marks {
                assertContrast(color, on: paperOrSlate, style: style, atLeast: 3.0, token: name)
            }
        }
    }

    /// The drill read-out's chip tints, measured where they are actually
    /// painted: 9pt tracked caps on a card, so `DS.surface`, so 4.5:1.
    ///
    /// Also pins that the flat verdict is tinted APART from the two movement
    /// verdicts. SHOWING UP LESS earns pine green; ABOUT THE SAME earns
    /// nothing, and must not be able to drift into a severity tint and start
    /// reading as good or bad news.
    func testDrillVerdictChipTintsClearAAAndStayDistinct() {
        let tones: [(String, DrillEffectPresentation.Tone)] = [
            ("receding", .receding), ("advancing", .advancing), ("flat", .flat),
        ]
        for style in [UIUserInterfaceStyle.light, .dark] {
            for (name, tone) in tones {
                assertContrast(tone.color, on: stockOrRaised, style: style,
                               atLeast: 4.5, token: "DrillEffectPresentation.Tone.\(name)")
            }
            let swatches = tones.map { hex(resolve($0.1.color, style)) }
            XCTAssertEqual(Set(swatches).count, tones.count,
                           "the drill verdict tones collapsed in "
                           + "\(style == .dark ? "DARK" : "LIGHT"): \(swatches). "
                           + "A verdict that measured no movement must not wear "
                           + "the colour of one that did.")
        }
    }

    /// Clearing AA is not the same as having a hierarchy.
    ///
    /// Light tertiary used to measure 2.50:1 on paper. Lifting it to the 5:1
    /// bar alone would have parked it almost on top of secondary, so the
    /// whole light ladder re-spaced to @100 / @82 / @64 — which seats three
    /// tiers inside the ~36 L* band between ink and the 5:1 contour on paper.
    /// That band is tight enough that a later "soften the captions" tweak
    /// could flatten the tiers into one grey while every assertion above
    /// still passes. So the spacing is pinned as well as the contrast.
    ///
    /// Metric is each tier's CIE L* distance from the ground it sits on,
    /// which must shrink monotonically down the ladder in both appearances.
    /// Light is held to a 12-point minimum step (it runs 18.6 / 16.8). Dark
    /// is held to order only: its lower two tiers sit 3.2 apart because
    /// raising tertiary to @58 for contrast on slate pushed it up under
    /// secondary. That compression is dark's own — the point of this test is
    /// that light must not be flattened to match it.
    func testInkLadderStaysPerceptiblyStepped() {
        let tiers = [("DS.ink", DS.ink),
                     ("DS.inkSecondary", DS.inkSecondary),
                     ("DS.inkTertiary", DS.inkTertiary)]

        for (style, minimumStep) in [(UIUserInterfaceStyle.light, 12.0), (.dark, 0.5)] {
            let appearance = style == .dark ? "DARK" : "LIGHT"
            let ground = resolve(DS.background, style)
            let groundLightness = lightness(ground)

            // Tonal separation from the ground, brightest-carrying tier first.
            let separations = tiers.map { name, color -> (String, Double) in
                (name, abs(groundLightness - lightness(composite(resolve(color, style), over: ground))))
            }

            for (above, below) in zip(separations, separations.dropFirst()) {
                XCTAssertGreaterThanOrEqual(
                    above.1 - below.1, minimumStep,
                    """
                    \(appearance) ink ladder is flat between \(above.0) and \(below.0).
                      \(above.0) sits \(String(format: "%.1f", above.1)) L* off DS.background
                      \(below.0) sits \(String(format: "%.1f", below.1)) L* off DS.background
                      step \(String(format: "%.1f", above.1 - below.1)) — required \(String(format: "%.1f", minimumStep))
                    Two tiers this close read as one grey: the ladder passes contrast \
                    but no longer expresses a hierarchy.
                    """)
            }
        }
    }

    /// Sanity: if `UIColor(Color)` ever stopped round-tripping the dynamic
    /// provider, every assertion above would silently measure light twice and
    /// still pass. Prove the two appearances actually differ.
    func testTokensResolveDifferentlyPerAppearance() {
        for (name, color) in [("DS.background", DS.background), ("DS.ink", DS.ink),
                              ("DS.severityModerate", DS.severityModerate)] {
            let light = resolve(color, .light)
            let dark = resolve(color, .dark)
            XCTAssertNotEqual(hex(light), hex(dark),
                              "\(name) resolved identically in light and dark (\(hex(light))) — "
                              + "the dynamic provider is not surviving UIColor(Color), so every "
                              + "contrast assertion in this file is measuring one appearance twice.")
        }
    }

    // MARK: - Assertion

    private func assertContrast(_ color: Color, on ground: Ground, style: UIUserInterfaceStyle,
                                atLeast required: Double, token: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        let groundRGBA = resolve(ground.color, style)
        let raw = resolve(color, style)
        let flattened = composite(raw, over: groundRGBA)
        let measured = contrastRatio(flattened, groundRGBA)

        XCTAssertGreaterThanOrEqual(
            measured, required,
            """
            \(token) fails WCAG in \(style == .dark ? "DARK" : "LIGHT").
              foreground \(token) = \(hex(raw))\(raw.a < 1 ? " @\(Int((raw.a * 100).rounded()))% → \(hex(flattened)) composited" : "")
              background \(ground.name) = \(hex(groundRGBA))
              measured \(String(format: "%.2f", measured)):1 — required \(String(format: "%.2f", required)):1 \
            (short by \(String(format: "%.2f", required - measured)))
            """,
            file: file, line: line)
    }

    // MARK: - WCAG maths

    private typealias RGBA = (r: Double, g: Double, b: Double, a: Double)

    private func resolve(_ color: Color, _ style: UIUserInterfaceStyle) -> RGBA {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            XCTFail("Could not read sRGB components from \(resolved)")
            return (0, 0, 0, 1)
        }
        return (Double(r), Double(g), Double(b), Double(a))
    }

    /// Source-over composite of a translucent token onto its opaque ground.
    private func composite(_ fg: RGBA, over bg: RGBA) -> RGBA {
        guard fg.a < 1 else { return fg }
        return (fg.r * fg.a + bg.r * (1 - fg.a),
                fg.g * fg.a + bg.g * (1 - fg.a),
                fg.b * fg.a + bg.b * (1 - fg.a),
                1)
    }

    /// WCAG 2.1 relative luminance.
    private func relativeLuminance(_ c: RGBA) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    /// CIE L* — perceptual lightness, 0 (black) to 100 (white). Contrast
    /// ratio answers "is this legible"; L* answers "does this read as a
    /// different tone", which is the question the ladder spacing asks.
    private func lightness(_ c: RGBA) -> Double {
        let y = relativeLuminance(c)
        return y > 0.008856 ? 116 * pow(y, 1.0 / 3.0) - 16 : 903.3 * y
    }

    private func contrastRatio(_ a: RGBA, _ b: RGBA) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func hex(_ c: RGBA) -> String {
        String(format: "#%02X%02X%02X",
               Int((min(max(c.r, 0), 1) * 255).rounded()),
               Int((min(max(c.g, 0), 1) * 255).rounded()),
               Int((min(max(c.b, 0), 1) * 255).rounded()))
    }
}
