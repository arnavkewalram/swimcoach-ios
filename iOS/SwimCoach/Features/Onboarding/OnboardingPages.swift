import SwiftUI

// MARK: - Onboarding pages
//
// The three EVENT pages hosted by OnboardingView's TabView. Each page
// opens with the shared EventMasthead (tracked kicker + heat counter over
// a LaneRule) and stays on the same leading 24pt grid as Home's masthead.
// The shell (OnboardingView.swift) owns the CTA, page ticks, and Skip.

// MARK: - Event masthead (kicker + heat counter + LaneRule)

private struct EventMasthead: View {
    let event: String       // "EVENT 01 · WELCOME"
    let index: Int          // 1-based page number
    let headline: String
    var headlineSize: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(event)
                    .font(.sectionLabel)
                    .tracking(2.0)
                    .foregroundStyle(DS.accent)
                Spacer()
                Text(String(format: "%02d / 03", index))
                    .font(.sectionLabel)
                    .tracking(1.2)
                    .foregroundStyle(DS.inkTertiary)
            }
            Text(headline)
                .font(.grotesk(headlineSize, .bold))
                .foregroundStyle(DS.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 10)
            LaneRule()
                .padding(.top, 16)
        }
    }
}

// MARK: - Page 1 · Welcome

struct WelcomePage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EventMasthead(event: "EVENT 01 · WELCOME", index: 1,
                          headline: "An AI swim coach\nin your pocket",
                          headlineSize: 36)

            Text("Film a swim from the pool deck — or import one from Photos — and get detailed biomechanics feedback in seconds.")
                .font(.subheadline)
                .lineSpacing(3)
                .foregroundStyle(DS.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            HStack(spacing: 8) {
                Rectangle()
                    .fill(DS.accent)
                    .frame(width: 16, height: 2)
                    .accessibilityHidden(true)
                Text("NO ACCOUNT REQUIRED")
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                    .tracking(1.4)
                    .foregroundStyle(DS.inkTertiary)
            }
            .padding(.top, 14)

            StatStrip()
                .padding(.top, 26)

            LaneFieldHero()
                .frame(maxHeight: 300)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.top, 20)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }
}

/// Entry-list data strip: the pipeline's real numbers set as meet-sheet
/// stats with hairline column rules.
private struct StatStrip: View {
    private let stats: [(value: String, label: String)] = [
        ("13", "JOINTS TRACKED"),
        ("30", "FRAMES PER SEC"),
        ("100%", "ON-DEVICE")
    ]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Array(stats.enumerated()), id: \.offset) { i, stat in
                if i > 0 {
                    Rectangle()
                        .fill(DS.border)
                        .frame(width: 1, height: 30)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(stat.value)
                        .font(.grotesk(20, .bold))
                        .foregroundStyle(DS.ink)
                    Text(stat.label)
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                        .tracking(1.1)
                        .foregroundStyle(DS.inkTertiary)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Composed hero: numbered pool lanes drawn with the LaneRule hairline
/// motif, filling the space below the copy — lanes distribute evenly,
/// the swimmer glyph rides lane 2 behind a fading wake, and a distance
/// annotation sits over the far end of lane 1.
private struct LaneFieldHero: View {
    private let lanes = 4

    private var swimmer: some View {
        HStack(alignment: .center, spacing: 7) {
            // Wake, fading out behind the swimmer
            Capsule().fill(DS.accent.opacity(0.20)).frame(width: 6, height: 2)
            Capsule().fill(DS.accent.opacity(0.40)).frame(width: 12, height: 2)
            Capsule().fill(DS.accent.opacity(0.65)).frame(width: 18, height: 2)
            Image(systemName: "figure.pool.swim")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(DS.accent)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(1...lanes, id: \.self) { lane in
                ZStack(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: 12) {
                        Text("\(lane)")
                            .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                            .foregroundStyle(DS.inkTertiary)
                            .offset(y: 3)
                        VStack(spacing: 3) {
                            Rectangle().fill(DS.border).frame(height: 1)
                            Rectangle().fill(DS.border).frame(height: 1)
                        }
                    }
                    if lane == 1 {
                        Text("FREESTYLE · 50M")
                            .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                            .tracking(1.2)
                            .foregroundStyle(DS.inkTertiary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.bottom, 12)
                    }
                    if lane == 2 {
                        swimmer
                            .padding(.leading, 34)
                            .offset(y: 6)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

// MARK: - Page 2 · Film

struct CameraPage: View {
    private let tips = [
        "Stable phone — watch the level line",
        "3–6 metres from the swimmer",
        "Bright lighting preferred"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EventMasthead(event: "EVENT 02 · FILM", index: 2,
                          headline: "Film from\nthe side")

            Text("Stand at the pool edge and film the full lane, with the swimmer's entire body visible from head to feet.")
                .font(.subheadline)
                .lineSpacing(3)
                .foregroundStyle(DS.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            SectionHeader(title: "Deck checklist")
                .padding(.top, 28)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(tips.enumerated()), id: \.offset) { i, tip in
                    HStack(spacing: 12) {
                        Text(String(format: "%02d", i + 1))
                            .font(.grotesk(13, .bold))
                            .foregroundStyle(DS.accent)
                        Text(tip)
                            .font(.subheadline)
                            .foregroundStyle(DS.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 13)
                    .accessibilityElement(children: .combine)
                    if i < tips.count - 1 {
                        Rectangle().fill(DS.border).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .glassCard()
            .padding(.top, 12)

            FramingDiagram()
                .frame(maxHeight: 250)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.top, 20)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }
}

/// Framing guide: a dashed viewfinder with the swimmer side-on riding a
/// LaneRule waterline — the shot the analyzer expects.
private struct FramingDiagram: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.borderBold, style: StrokeStyle(lineWidth: 1, dash: [6, 5]))

            VStack(spacing: 0) {
                HStack {
                    Text("CAMERA FRAME")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                        .tracking(1.2)
                        .foregroundStyle(DS.inkTertiary)
                    Spacer()
                    Text("SIDE-ON")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                        .tracking(1.2)
                        .foregroundStyle(DS.accent)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                Spacer(minLength: 8)

                Image(systemName: "figure.pool.swim")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(DS.accent)
                    .offset(y: 9)
                VStack(spacing: 3) {
                    Rectangle().fill(DS.border).frame(height: 1)
                    Rectangle().fill(DS.border).frame(height: 1)
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    Rectangle().fill(DS.accent).frame(width: 16, height: 2)
                    Text("FULL BODY VISIBLE — HEAD TO FEET")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                        .tracking(1.2)
                        .foregroundStyle(DS.inkTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Framing guide: film side-on with the swimmer's full body visible, head to feet")
    }
}

// MARK: - Page 3 · Results

struct ResultsPage: View {
    private enum Detail { case score, severities, none }

    private struct ResultCard: View {
        let index: String
        let title: String
        let description: String
        let mark: Color
        var detail: Detail = .none

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(index)
                        .font(.grotesk(13, .bold))
                        .foregroundStyle(DS.accent)
                    Text(title)
                        .font(.grotesk(15, .medium))
                        .foregroundStyle(DS.ink)
                    Spacer(minLength: 0)
                    if case .score = detail {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("82")
                                .font(.grotesk(20, .bold))
                                .foregroundStyle(DS.accent)
                            Text("B")
                                .font(.grotesk(12, .medium))
                                .foregroundStyle(DS.inkTertiary)
                        }
                    }
                }
                Text(description)
                    .font(.footnote)
                    .lineSpacing(3)
                    .foregroundStyle(DS.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .severities = detail {
                    HStack(spacing: 6) {
                        SeverityBadge(severity: "major")
                        SeverityBadge(severity: "moderate")
                        SeverityBadge(severity: "minor")
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassCard()
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                    .fill(mark)
                    .frame(width: 3)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EventMasthead(event: "EVENT 03 · RESULTS", index: 3,
                          headline: "What you'll get")

            SectionHeader(title: "Every session")
                .padding(.top, 24)

            VStack(spacing: 10) {
                ResultCard(index: "01", title: "Technique score",
                           description: "A 0–100 biomechanics score with a letter grade",
                           mark: DS.accent, detail: .score)
                ResultCard(index: "02", title: "Faults, on your video",
                           description: "Named stroke faults with severity — and a skeleton overlay showing exactly when they happened",
                           mark: DS.severityMajor, detail: .severities)
                ResultCard(index: "03", title: "Drills & progress",
                           description: "A drill library mapped to every fault, plus trends, weekly goals, and a focus to work on",
                           mark: DS.severityMinor)
            }
            .padding(.top, 12)

            Spacer(minLength: 16)

            // Progress preview in Home's training-log register.
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("SAMPLE TREND")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                        .tracking(1.2)
                        .foregroundStyle(DS.inkTertiary)
                    LaneRule()
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text("+14 PTS")
                            .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                            .tracking(1.2)
                    }
                    .foregroundStyle(DS.severityMinor)
                }
                Sparkline(values: [58, 61, 60, 64, 63, 67, 66, 70, 69, 72])
                    .frame(height: 36)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sample trend: technique score rising fourteen points across three weeks")
            .padding(.bottom, 18)

            HStack(spacing: 8) {
                Rectangle()
                    .fill(DS.accent)
                    .frame(width: 16, height: 2)
                    .accessibilityHidden(true)
                Text("EVERY SWIM SAVED TO YOUR HISTORY")
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                    .tracking(1.4)
                    .foregroundStyle(DS.inkTertiary)
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }
}
