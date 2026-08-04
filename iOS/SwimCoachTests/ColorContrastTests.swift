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
            .init(token: "DS.inkSecondary", color: DS.inkSecondary,
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

    /// KNOWN GAP — not a claim of compliance.
    ///
    /// `DS.inkTertiary` light composites to ~2.50:1 on paper: it fails AA for
    /// the captions and unit labels it tints, while the dark step clears 5:1.
    /// Closing it means re-spacing the whole light ink ladder (tertiary would
    /// land on top of secondary), which is a design decision, not a token
    /// tweak. Until then this pins the current value as a floor so the gap
    /// cannot widen unnoticed, and holds dark to the 5:1 bar it was raised to.
    func testInkTertiaryHoldsItsFloor() {
        assertContrast(DS.inkTertiary, on: paperOrSlate, style: .light,
                       atLeast: 2.45, token: "DS.inkTertiary (KNOWN AA GAP)")
        assertContrast(DS.inkTertiary, on: stockOrRaised, style: .light,
                       atLeast: 2.45, token: "DS.inkTertiary (KNOWN AA GAP)")
        assertContrast(DS.inkTertiary, on: paperOrSlate, style: .dark,
                       atLeast: 5.0, token: "DS.inkTertiary")
        assertContrast(DS.inkTertiary, on: stockOrRaised, style: .dark,
                       atLeast: 5.0, token: "DS.inkTertiary")
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
