import SwiftUI
import SwiftData

/// About: what the app is, the on-device privacy stance, and the type
/// license we're obliged to ship (Space Grotesk, SIL OFL).
struct AboutView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SwimSession.analyzedAt, order: .reverse) private var sessions: [SwimSession]
    @Query private var practiceEvents: [DrillPracticeEvent]
    @State private var showLicense = false
    @State private var exportURL: URL? = nil
    @State private var csvExportURL: URL? = nil
    @State private var confirmErase = false

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

                    if !sessions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Your data")
                            Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s") stored on this iPhone.")
                                .font(.footnote)
                                .foregroundStyle(DS.inkSecondary)

                            if let exportURL {
                                ShareLink(item: exportURL) {
                                    dataActionLabel("EXPORT JSON ARCHIVE", icon: "square.and.arrow.up",
                                                    color: DS.accent)
                                }
                            } else {
                                Button {
                                    prepareExport()
                                } label: {
                                    dataActionLabel("PREPARE JSON ARCHIVE", icon: "doc.text",
                                                    color: DS.accent)
                                }
                            }

                            if let csvExportURL {
                                ShareLink(item: csvExportURL) {
                                    dataActionLabel("EXPORT CSV SPREADSHEET", icon: "square.and.arrow.up",
                                                    color: DS.accent)
                                }
                            } else {
                                Button {
                                    prepareCSVExport()
                                } label: {
                                    dataActionLabel("PREPARE CSV SPREADSHEET", icon: "tablecells",
                                                    color: DS.accent)
                                }
                            }

                            Button(role: .destructive) {
                                confirmErase = true
                            } label: {
                                dataActionLabel("ERASE ALL SESSIONS", icon: "trash",
                                                color: DS.severityMajor)
                            }
                        }
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
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
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
        .confirmationDialog(
            "Erase all \(sessions.count) sessions?",
            isPresented: $confirmErase, titleVisibility: .visible
        ) {
            Button("Erase everything", role: .destructive) { eraseAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes every saved session and its video. This cannot be undone.")
        }
    }

    private func dataActionLabel(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .accessibilityHidden(true)
            Text(title)
                .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                .tracking(1.2)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.45), lineWidth: 1))
        // Pill stays visually compact; the frame extends the tap target
        // to the HIG 44pt minimum.
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func prepareExport() {
        do {
            let data = try SessionExport.archiveData(from: sessions, practice: practiceEvents)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("swimcoach-training-log.json")
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            AppLog.storage.error("Training log export failed: \(error.localizedDescription)")
        }
    }

    private func prepareCSVExport() {
        do {
            let csv = SessionCSV.csv(from: sessions)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("swimcoach-training-log.csv")
            try Data(csv.utf8).write(to: url, options: .atomic)
            csvExportURL = url
        } catch {
            AppLog.storage.error("CSV export failed: \(error.localizedDescription)")
        }
    }

    private func eraseAll() {
        for session in sessions {
            modelContext.delete(session)
        }
        // Erase deletes the store outright rather than sweeping it. The sweeper
        // is retention-aware — it holds unclaimed clips for a week and offers
        // them back on Home — and every video here looks unclaimed now that the
        // sessions are gone, so a sweep would leave the last week of swims on
        // disk and then resurrect them as recoverable takes. The dialog
        // promises this cannot be undone, so retention does not apply.
        SessionVideoStore.removeAll()
        for event in practiceEvents { modelContext.delete(event) }
        exportURL = nil
        csvExportURL = nil
    }
}
