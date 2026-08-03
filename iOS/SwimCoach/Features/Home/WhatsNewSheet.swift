import SwiftUI

/// Once-per-version release notes in the editorial register.
struct WhatsNewSheet: View {
    let onDismiss: () -> Void

    /// Fade zone above the pinned Continue button so highlights scrolled
    /// beneath it dissolve into the ground instead of hard-clipping.
    private static let scrimHeight: CGFloat = 36

    var body: some View {
        ZStack {
            DS.sheetSurface.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text("WHAT'S NEW")
                    .font(.sectionLabel)
                    .tracking(2.0)
                    .foregroundStyle(DS.accent)
                    .padding(.bottom, 6)

                Text("SwimCoach \(WhatsNew.currentVersion)")
                    .font(.grotesk(28, .bold))
                    .foregroundStyle(DS.ink)
                    .padding(.bottom, 18)

                LaneRule()
                    .padding(.bottom, 18)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(WhatsNew.highlights) { item in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: item.icon)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(DS.accent)
                                    .frame(width: 26)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.grotesk(16, .bold))
                                        .foregroundStyle(DS.ink)
                                    Text(item.detail)
                                        .font(.footnote)
                                        .lineSpacing(3)
                                        .foregroundStyle(DS.inkSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.bottom, 16)
                }
                // Pin Continue as a bottom inset: the scroll content is
                // automatically padded by the full inset height (button +
                // scrim), so at the medium detent the last highlight can
                // always scroll clear of the button, and anything mid-scroll
                // fades through the scrim instead of severing.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [DS.background.opacity(0), DS.background],
                            startPoint: .top,
                            endPoint: .bottom)
                            .frame(height: Self.scrimHeight)
                            .allowsHitTesting(false)

                        Button(action: onDismiss) {
                            PrimaryButtonLabel(title: "Continue")
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .background(DS.background)
                    }
                }
            }
            .padding(24)
        }
        .interactiveDismissDisabled(false)
    }
}
