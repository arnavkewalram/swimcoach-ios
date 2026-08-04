import SwiftUI
import SwiftData

/// About: what the app is, the on-device privacy stance, and the type
/// license we're obliged to ship (Space Grotesk, SIL OFL).
struct AboutView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SwimSession.analyzedAt, order: .reverse) private var sessions: [SwimSession]
    @Query private var practiceEvents: [DrillPracticeEvent]
    @State private var showLicense = false
    @State private var archiveExport: DataExportState = .idle
    @State private var csvExport: DataExportState = .idle
    @State private var confirmErase = false

    /// Prepare → share, with the file build in between. Mirrors
    /// `ResultsView.VideoExportState`; the file here is small enough that
    /// there is nothing meaningful to report but "working".
    enum DataExportState: Equatable {
        case idle, preparing, ready(URL), failed
    }

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

                            dataExportControl(state: archiveExport, noun: "JSON ARCHIVE",
                                              icon: "doc.text", prepare: prepareExport)

                            dataExportControl(state: csvExport, noun: "CSV SPREADSHEET",
                                              icon: "tablecells", prepare: prepareCSVExport)

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
        dataActionLabel(title, color: color) {
            Image(systemName: icon)
                .font(.caption)
                .accessibilityHidden(true)
        }
    }

    private func dataActionLabel<Leading: View>(
        _ title: String, color: Color, @ViewBuilder leading: () -> Leading
    ) -> some View {
        HStack(spacing: 6) {
            leading()
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

    /// One export row: prepare button → spinner while the file builds →
    /// ShareLink. A failure falls back to a retry button rather than
    /// leaving the row stuck mid-spin.
    @ViewBuilder
    private func dataExportControl(state: DataExportState, noun: String, icon: String,
                                   prepare: @escaping () -> Void) -> some View {
        switch state {
        case .idle, .failed:
            Button(action: prepare) {
                dataActionLabel(state == .failed ? "RETRY \(noun)" : "PREPARE \(noun)",
                                icon: state == .failed ? "arrow.clockwise" : icon,
                                color: state == .failed ? DS.severityMajor : DS.accent)
            }
        case .preparing:
            dataActionLabel("PREPARING \(noun)", color: DS.inkTertiary) {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel("Preparing \(noun.lowercased())")
        case .ready(let url):
            ShareLink(item: url) {
                dataActionLabel("EXPORT \(noun)", icon: "square.and.arrow.up", color: DS.accent)
            }
        }
    }

    // MARK: - Export

    // Both exports snapshot the fetched models into `Sendable` values here on
    // the main actor — where the `@Query` results and their `ModelContext`
    // live — and then hand only those values to `TrainingLogWriter`, whose
    // nonisolated `async` entry points run the encoding and the file write
    // off the main thread. Passing the `@Model` objects across instead would
    // read them off their context's actor, which is a race, not a speedup.

    @MainActor
    private func prepareExport() {
        let sessionSnapshots = sessions.map { SessionSnapshot(session: $0) }
        let practiceSnapshots = practiceEvents.map { PracticeSnapshot(event: $0) }
        archiveExport = .preparing
        Task {
            do {
                archiveExport = .ready(try await TrainingLogWriter.writeArchive(
                    sessions: sessionSnapshots, practice: practiceSnapshots))
            } catch {
                AppLog.storage.error("Training log export failed: \(error.localizedDescription)")
                archiveExport = .failed
            }
        }
    }

    @MainActor
    private func prepareCSVExport() {
        let sessionSnapshots = sessions.map { SessionSnapshot(session: $0) }
        csvExport = .preparing
        Task {
            do {
                csvExport = .ready(try await TrainingLogWriter.writeCSV(
                    sessions: sessionSnapshots))
            } catch {
                AppLog.storage.error("CSV export failed: \(error.localizedDescription)")
                csvExport = .failed
            }
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
        archiveExport = .idle
        csvExport = .idle
    }
}
