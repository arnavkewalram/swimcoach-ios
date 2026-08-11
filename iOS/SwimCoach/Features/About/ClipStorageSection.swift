import SwiftUI

/// What the stored footage costs, and the one control that can drop it without
/// touching a swim.
///
/// About could always say how many sessions exist; it could never say what
/// they weigh, and the only destructive lever on the screen — ERASE ALL
/// SESSIONS — takes the scores with the video. This is the other lever: the
/// analysis is small, the footage is not, and a swimmer who wants their
/// history without their films should be able to say so.
///
/// The whole policy lives in `VideoStorage`, which is pure and exhaustively
/// tested. This view only renders it and asks for confirmation.
struct ClipStorageSection: View {
    /// Saved-session ids, passed in rather than re-queried. About already
    /// holds the `@Query`, and "claimed" has to be decided from exactly the
    /// column the launch sweep decides it from — one definition, one source.
    ///
    /// It doubles as the refresh trigger: erasing every session empties this,
    /// which is precisely when the numbers below stop being true.
    let referencedIDs: Set<String>

    @State private var storage: VideoStorage.Summary = .empty
    @State private var selectedCutoff: VideoStorage.Cutoff?
    @State private var confirmDelete = false

    /// The selection marker beside each age row. Scaled so it still reads as
    /// a rule beside the label at accessibility sizes instead of a speck.
    @ScaledMetric(relativeTo: .caption2) private var cutoffMarkHeight: CGFloat = 16

    // MARK: - Body

    /// Hidden entirely when the store is empty — there is nothing to report
    /// and nothing to delete. When files exist but none of them belongs to a
    /// saved session (only unfinished takes are waiting), the total is still
    /// worth showing but the delete control is not offered: every age it could
    /// name would delete nothing.
    var body: some View {
        Group {
            if !storage.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Clip storage")

                    headline

                    Text(breakdown)
                        .font(.footnote)
                        .lineSpacing(4)
                        .foregroundStyle(DS.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if storage.hasDeletableClips {
                        deleteControl
                    } else {
                        Text("No saved swim has a clip to play. What is here is waiting to be scored — the Takes screen decides those.")
                            .font(.footnote)
                            .lineSpacing(4)
                            .foregroundStyle(DS.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("clipStorageEmptyNote")
                    }
                }
            }
        }
        .task { refresh() }
        // Erase-all deletes every session, so the ids change and the footage
        // this was pricing a moment ago no longer exists. Reacting to the
        // referenced set rather than being told to refresh keeps the two
        // destructive controls from having to know about each other.
        .onChange(of: referencedIDs) { refresh() }
        .confirmationDialog(confirmTitle, isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            if let pending {
                Button("Delete \(VideoStorage.clipCountText(pending.count))",
                       role: .destructive) { deleteClips(pending) }
            }
            Button("Keep them", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    // MARK: - Pieces

    /// The number that was missing: megabytes, not session count.
    private var headline: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                totalText.fixedSize(horizontal: true, vertical: false)
                countText.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 4) {
                totalText
                countText
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(VideoStorage.sizeText(storage.totalByteCount)) of video stored, "
                            + "in \(VideoStorage.clipCountText(storage.fileCount)).")
        .accessibilityIdentifier("clipStorageTotal")
    }

    private var totalText: some View {
        Text(VideoStorage.sizeText(storage.totalByteCount))
            .font(.grotesk(30, .bold))
            .monospacedDigit()
            .foregroundStyle(DS.ink)
    }

    private var countText: some View {
        Text("IN \(VideoStorage.clipCountText(storage.fileCount).uppercased())")
            .font(.statUnit)
            .tracking(1.2)
            .foregroundStyle(DS.inkTertiary)
    }

    private var breakdown: String {
        let claimed = "\(VideoStorage.clipCountText(storage.sessionClipCount)) belong to saved swims"
        guard storage.unscoredCount > 0 else { return "\(claimed)." }
        return "\(claimed); \(storage.unscoredCount) "
            + "\(storage.unscoredCount == 1 ? "is" : "are") still waiting to be scored."
    }

    @ViewBuilder
    private var deleteControl: some View {
        Text("DELETE CLIPS OLDER THAN")
            .font(.sectionLabel)
            .tracking(1.4)
            .foregroundStyle(DS.inkTertiary)
            .padding(.top, 6)

        VStack(spacing: 0) {
            ForEach(Array(VideoStorage.cutoffs.enumerated()), id: \.element.id) { index, cutoff in
                if index > 0 {
                    Rectangle().fill(DS.border).frame(height: 1)
                }
                cutoffRow(cutoff)
            }
        }

        if let pending {
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                DataActionLabel(
                    title: "DELETE \(VideoStorage.clipCountText(pending.count).uppercased())",
                    adornment: .icon("trash"), tint: DS.severityMajor)
            }
            .accessibilityLabel("Delete \(VideoStorage.clipCountText(pending.count)), "
                                + "\(VideoStorage.sizeText(pending.byteCount))")
            .accessibilityIdentifier("clipStorageDelete")
        }

        Text("Scores, faults, notes and trends stay — nothing leaves your history. The footage goes, so those swims will have no clip to play.")
            .font(.footnote)
            .lineSpacing(4)
            .foregroundStyle(DS.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - The offer on the table

    /// The selected offer, or nil when nothing is selected or the selection
    /// would free nothing — the delete button reads this, so it cannot appear
    /// over an empty set.
    private var pending: VideoStorage.Selection? {
        guard let selectedCutoff else { return nil }
        let offer = storage.offer(for: selectedCutoff)
        return offer.isEmpty ? nil : offer
    }

    private var confirmTitle: String {
        guard let pending else { return "Delete clips?" }
        return "Delete \(VideoStorage.clipCountText(pending.count))?"
    }

    /// States what goes and what stays before the user commits — the same
    /// standard of care "Erase all sessions" is held to, applied to a delete
    /// whose entire point is that it is NOT that.
    ///
    /// Vocabulary is deliberately v1.47.2's: a swim whose footage this drops
    /// reads "no clip to play" everywhere afterwards, so that is what the
    /// dialog promises rather than a fourth phrasing of the same fact.
    private var confirmMessage: String {
        guard let pending else { return "" }
        let takesNote = storage.unscoredCount > 0
            ? " Clips waiting to be scored are not touched."
            : ""
        let kept = pending.count == 1
            ? "That session keeps its score, faults, notes and trends — only the video goes, "
              + "so it will have no clip to play."
            : "Those sessions keep their score, faults, notes and trends — only the video goes, "
              + "so they will have no clip to play."
        return "Frees \(VideoStorage.sizeText(pending.byteCount)) by deleting "
            + "\(VideoStorage.clipCountText(pending.count)) \(pending.cutoff.phrase). "
            + "\(kept)\(takesNote) This cannot be undone."
    }

    // MARK: - Actions

    private func refresh() {
        storage = SessionVideoStore.storageSummary(referencedIDs: referencedIDs)
        // Never leave a live delete button pointing at an offer that has since
        // emptied — after a delete, the selection has to move or clear.
        let stillOffered = selectedCutoff.map { !storage.offer(for: $0).isEmpty } ?? false
        if !stillOffered { selectedCutoff = storage.defaultCutoff }
    }

    /// Deletes the offer the dialog named, not a freshly re-derived one, so
    /// the count and the megabytes the user agreed to are the ones that go.
    private func deleteClips(_ selection: VideoStorage.Selection) {
        SessionVideoStore.deleteSessionClips(selection, referencedIDs: referencedIDs)
        refresh()
    }
}
