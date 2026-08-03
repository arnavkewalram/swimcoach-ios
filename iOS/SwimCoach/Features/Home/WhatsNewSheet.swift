import SwiftUI

/// Once-per-version release notes in the editorial register.
struct WhatsNewSheet: View {
    let onDismiss: () -> Void

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

                Button(action: onDismiss) {
                    PrimaryButtonLabel(title: "Continue")
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(24)
        }
        .interactiveDismissDisabled(false)
    }
}
