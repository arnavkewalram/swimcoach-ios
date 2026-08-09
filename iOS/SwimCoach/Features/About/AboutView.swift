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

    // Clip storage: what the footage weighs, and the age the user has drawn
    // the line at. `selectedCutoff` is nil only when nothing is deletable.
    @State private var storage: VideoStorage.Summary = .empty
    @State private var selectedCutoff: VideoStorage.Cutoff?
    @State private var confirmClipDelete = false

    /// The selection marker beside each age row. Scaled so it still reads as
    /// a rule beside the label at accessibility sizes instead of a speck.
    @ScaledMetric(relativeTo: .caption2) private var cutoffMarkHeight: CGFloat = 16

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

                    clipStorageSection

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
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-seedStoredClips") {
                seedStoredClips()
            }
            #endif
            refreshStorage()
        }
        .confirmationDialog(
            "Erase all \(sessions.count) sessions?",
            isPresented: $confirmErase, titleVisibility: .visible
        ) {
            Button("Erase everything", role: .destructive) { eraseAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes every saved session and its video. This cannot be undone.")
        }
        .confirmationDialog(clipDeleteTitle, isPresented: $confirmClipDelete,
                            titleVisibility: .visible) {
            if let pending = pendingDeletion {
                Button("Delete \(VideoStorage.clipCountText(pending.count))",
                       role: .destructive) { deleteClips() }
            }
            Button("Keep them", role: .cancel) {}
        } message: {
            Text(clipDeleteMessage)
        }
    }

    // MARK: - Clip storage

    /// What the footage costs, and the one control that can drop it without
    /// touching a swim.
    ///
    /// Hidden entirely when the store is empty — there is nothing to report
    /// and nothing to delete. When files exist but none of them belongs to a
    /// saved session (only unfinished takes are waiting), the total is still
    /// worth showing but the delete control is not offered: every age it could
    /// name would delete nothing.
    @ViewBuilder
    private var clipStorageSection: some View {
        if !storage.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Clip storage")

                storageHeadline

                Text(storageBreakdown)
                    .font(.footnote)
                    .lineSpacing(4)
                    .foregroundStyle(DS.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if storage.hasDeletableClips {
                    Text("DELETE CLIPS OLDER THAN")
                        .font(.sectionLabel)
                        .tracking(1.4)
                        .foregroundStyle(DS.inkTertiary)
                        .padding(.top, 6)

                    VStack(spacing: 0) {
                        ForEach(Array(VideoStorage.cutoffs.enumerated()), id: \.element.id) {
                            index, cutoff in
                            if index > 0 {
                                Rectangle().fill(DS.border).frame(height: 1)
                            }
                            cutoffRow(cutoff)
                        }
                    }

                    if let pending = pendingDeletion {
                        Button(role: .destructive) {
                            confirmClipDelete = true
                        } label: {
                            dataActionLabel(
                                "DELETE \(VideoStorage.clipCountText(pending.count).uppercased())",
                                icon: "trash", color: DS.severityMajor)
                        }
                        .accessibilityLabel(
                            "Delete \(VideoStorage.clipCountText(pending.count)), "
                            + "\(VideoStorage.sizeText(pending.byteCount))")
                        .accessibilityIdentifier("clipStorageDelete")
                    }

                    Text("Scores, faults, notes and trends stay — nothing leaves your history. The footage goes, so those swims can no longer be played back.")
                        .font(.footnote)
                        .lineSpacing(4)
                        .foregroundStyle(DS.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No saved swim has a stored clip. What is here is waiting to be scored — the Takes screen decides those.")
                        .font(.footnote)
                        .lineSpacing(4)
                        .foregroundStyle(DS.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("clipStorageEmptyNote")
                }
            }
        }
    }

    /// The number that was missing: megabytes, not session count.
    private var storageHeadline: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                storageTotalText.fixedSize(horizontal: true, vertical: false)
                storageCountText.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 4) {
                storageTotalText
                storageCountText
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(VideoStorage.sizeText(storage.totalByteCount)) of video stored, "
                            + "in \(VideoStorage.clipCountText(storage.fileCount)).")
        .accessibilityIdentifier("clipStorageTotal")
    }

    private var storageTotalText: some View {
        Text(VideoStorage.sizeText(storage.totalByteCount))
            .font(.grotesk(30, .bold))
            .monospacedDigit()
            .foregroundStyle(DS.ink)
    }

    private var storageCountText: some View {
        Text("IN \(VideoStorage.clipCountText(storage.fileCount).uppercased())")
            .font(.statUnit)
            .tracking(1.2)
            .foregroundStyle(DS.inkTertiary)
    }

    private var storageBreakdown: String {
        let claimed = "\(VideoStorage.clipCountText(storage.sessionClipCount)) belong to saved swims"
        guard storage.unscoredCount > 0 else { return "\(claimed)." }
        return "\(claimed); \(storage.unscoredCount) "
            + "\(storage.unscoredCount == 1 ? "is" : "are") still waiting to be scored."
    }

    /// One age the user can draw the line at, priced. A row that would free
    /// nothing says so and cannot be selected — the control never offers to
    /// delete zero clips.
    private func cutoffRow(_ cutoff: VideoStorage.Cutoff) -> some View {
        let offer = storage.offer(for: cutoff)
        let isSelected = selectedCutoff == cutoff
        return Button {
            selectedCutoff = cutoff
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? DS.accent : DS.border)
                    .frame(width: 3, height: cutoffMarkHeight)
                    .accessibilityHidden(true)

                // Pinned to one line in the horizontal branch so a row that
                // genuinely cannot hold both halves falls to the stack instead
                // of wrapping the label into the price.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        cutoffLabel(cutoff, isSelected: isSelected, isEmpty: offer.isEmpty)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 8)
                        cutoffPrice(offer).fixedSize(horizontal: true, vertical: false)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        cutoffLabel(cutoff, isSelected: isSelected, isEmpty: offer.isEmpty)
                        cutoffPrice(offer)
                    }
                }
            }
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .disabled(offer.isEmpty)
        .accessibilityLabel(
            offer.isEmpty
                ? "Older than \(cutoff.spoken): no clips this old"
                : "Delete clips older than \(cutoff.spoken): "
                  + "\(VideoStorage.clipCountText(offer.count)), \(VideoStorage.sizeText(offer.byteCount))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("clipStorageCutoff-\(cutoff.id)")
    }

    private func cutoffLabel(_ cutoff: VideoStorage.Cutoff,
                             isSelected: Bool, isEmpty: Bool) -> some View {
        Text(cutoff.label)
            .font(.sectionLabel)
            .tracking(1.2)
            .foregroundStyle(isEmpty ? DS.inkTertiary : (isSelected ? DS.ink : DS.inkSecondary))
    }

    private func cutoffPrice(_ offer: VideoStorage.Selection) -> some View {
        Text(offer.isEmpty
             ? "None this old"
             : "\(VideoStorage.clipCountText(offer.count)) · \(VideoStorage.sizeText(offer.byteCount))")
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(offer.isEmpty ? DS.inkTertiary : DS.inkSecondary)
    }

    /// The selected offer, or nil when nothing is selected or the selection
    /// would free nothing — the delete button reads this, so it cannot appear
    /// over an empty set.
    private var pendingDeletion: VideoStorage.Selection? {
        guard let selectedCutoff else { return nil }
        let offer = storage.offer(for: selectedCutoff)
        return offer.isEmpty ? nil : offer
    }

    private var clipDeleteTitle: String {
        guard let pending = pendingDeletion else { return "Delete clips?" }
        return "Delete \(VideoStorage.clipCountText(pending.count))?"
    }

    /// States what goes and what stays before the user commits — the same
    /// standard of care "Erase all sessions" is held to, applied to a delete
    /// whose entire point is that it is NOT that.
    private var clipDeleteMessage: String {
        guard let pending = pendingDeletion else { return "" }
        let takesNote = storage.unscoredCount > 0
            ? " Clips waiting to be scored are not touched."
            : ""
        let kept = pending.count == 1
            ? "That session keeps its score, faults, notes and trends — only the video goes, "
              + "so it can no longer be played back."
            : "Those sessions keep their score, faults, notes and trends — only the video goes, "
              + "so they can no longer be played back."
        return "Frees \(VideoStorage.sizeText(pending.byteCount)) by deleting "
            + "\(VideoStorage.clipCountText(pending.count)) \(pending.cutoff.phrase). "
            + "\(kept)\(takesNote) This cannot be undone."
    }

    private func refreshStorage() {
        storage = SessionVideoStore.storageSummary(referencedIDs: referencedSessionIDs)
        // Never leave a live delete button pointing at an offer that has since
        // emptied — after a delete, the selection has to move or clear.
        let stillOffered = selectedCutoff.map { !storage.offer(for: $0).isEmpty } ?? false
        if !stillOffered { selectedCutoff = storage.defaultCutoff }
    }

    private func deleteClips() {
        guard let cutoff = selectedCutoff else { return }
        SessionVideoStore.deleteSessionClips(olderThan: cutoff,
                                             referencedIDs: referencedSessionIDs)
        refreshStorage()
    }

    /// Session membership from the cheap stored `id` column — no result blob
    /// is decoded, the same rule the launch sweep follows.
    private var referencedSessionIDs: Set<String> {
        Set(sessions.map(\.id.uuidString))
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
        // The store is empty now; the clip-storage section has to stop
        // reporting the megabytes it held a moment ago.
        storage = .empty
        selectedCutoff = nil
    }

    #if DEBUG
    /// Simulator fixture for the clip-storage section. Recording is the only
    /// thing that fills the store for real and the simulator has no camera, so
    /// this copies the bundled clip in under the ids of the newest saved
    /// sessions — the `<result-id>.<ext>` invariant, hence genuinely claimed
    /// files — and back-dates them across the offered cutoffs so every age row
    /// prices something different. Pairs with `-seedTrainingLog`, which
    /// creates the sessions these clips are claimed by.
    ///
    /// Each session is also repointed at its own copy, so the fixture is the
    /// real relationship rather than a lookalike: Results plays these clips
    /// before the delete and has no video section after it.
    private func seedStoredClips() {
        guard let source = Bundle.main.url(forResource: "swim_test", withExtension: "mp4")
        else { return }
        for (session, daysAgo) in zip(sessions, [1, 45, 120, 500]) {
            let name = "\(session.id.uuidString).mp4"
            let dest = SessionVideoStore.directory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            guard (try? FileManager.default.copyItem(at: source, to: dest)) != nil else { continue }
            try? FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-Double(daysAgo) * 24 * 60 * 60)],
                ofItemAtPath: dest.path)
            guard var result = session.decoded() else { continue }
            result.videoFileName = name
            session.resultData = (try? JSONEncoder().encode(result)) ?? session.resultData
        }
    }
    #endif
}
