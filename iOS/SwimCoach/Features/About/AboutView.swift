import SwiftUI

/// About: what the app is, the on-device privacy stance, and the type
/// license we're obliged to ship (Space Grotesk, SIL OFL).
struct AboutView: View {
    @State private var showLicense = false

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(version) (\(build))"
    }

    private var licenseText: String? {
        guard let url = Bundle.main.url(forResource: "OFL", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text
    }

    var body: some View {
        ZStack {
            DS.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SwimCoach")
                            .font(.grotesk(34, .bold))
                            .foregroundStyle(DS.ink)
                        Text(versionLine.uppercased())
                            .font(.sectionLabel)
                            .tracking(1.4)
                            .foregroundStyle(DS.inkTertiary)
                    }
                    .padding(.top, 16)

                    LaneRule()

                    Text("SwimCoach films a freestyle swim and scores its biomechanics with SwimTCN, a temporal neural network trained on stroke mechanics. It detects faults like body sag, elbow collapse, and kick-timing problems, then maps each one to drills.")
                        .font(.footnote)
                        .lineSpacing(4)
                        .foregroundStyle(DS.inkSecondary)

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Privacy")
                        Text("Everything runs on your iPhone. Videos, pose data, and results never leave the device — there is no account, no upload, and no analytics.")
                            .font(.footnote)
                            .lineSpacing(4)
                            .foregroundStyle(DS.inkSecondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Type")
                        Text("Set in Space Grotesk by Florian Karsten, used under the SIL Open Font License 1.1.")
                            .font(.footnote)
                            .lineSpacing(4)
                            .foregroundStyle(DS.inkSecondary)

                        if let licenseText {
                            Button {
                                withAnimation(.snappy(duration: 0.2)) { showLicense.toggle() }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(showLicense ? "HIDE LICENSE" : "VIEW LICENSE")
                                        .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                                        .tracking(1.2)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8, weight: .semibold))
                                        .rotationEffect(.degrees(showLicense ? 180 : 0))
                                        .accessibilityHidden(true)
                                }
                                .foregroundStyle(DS.accent)
                            }

                            if showLicense {
                                Text(licenseText)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(DS.inkSecondary)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(DS.surface2)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 24)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("About")
                    .font(.grotesk(17, .medium))
                    .foregroundStyle(DS.ink)
            }
        }
        .toolbarBackground(DS.background, for: .navigationBar)
    }
}
