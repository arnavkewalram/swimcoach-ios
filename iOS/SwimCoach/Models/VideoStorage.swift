import Foundation

/// What the stored clips cost, and which of them "keep the swim, drop the
/// footage" is allowed to delete.
///
/// The app has always been able to survive a missing clip — `videoURL`
/// resolves to nil, Results drops its video section, Compare says the side has
/// none — but it has never offered the user a way to ask for that. Erasing
/// everything was the only lever, and it takes the scores with it. This is the
/// policy behind the other lever: the analysis is small, the video is not, and
/// a swimmer who wants their history without their footage should be able to
/// say so.
///
/// Pure by construction — a directory listing plus the saved session ids in,
/// totals and file names out. No `FileManager`, no SwiftData. The decision that
/// destroys video is the one thing here worth testing exhaustively, and it can
/// be tested without a disk.
///
/// One rule carries the whole feature: **only a clip a saved session claims is
/// ever a candidate.** An unclaimed file is an unfinished take — a lap that was
/// filmed and never scored, whose video IS the swim. Deleting it here would
/// lose the swim outright, which is the opposite of what this offers, and it
/// would reach past `UnfinishedTakes` into a population that already has its
/// own retention window and its own delete button. So takes are counted in the
/// total the user sees and are never in the delete set.
enum VideoStorage {

    // MARK: - Age offers

    /// One age the user can draw the line at.
    struct Cutoff: Identifiable, Hashable {
        /// Age in days a clip must exceed to be deleted. Nil means no age
        /// limit at all — every session clip qualifies, which is the swimmer
        /// who wants the numbers and none of the footage.
        let days: Int?
        /// Row label, ALL CAPS to sit in the meet-sheet label tier.
        let label: String
        /// Completes "Deletes N clips …" in the confirmation, so the dialog
        /// names the same boundary the row does.
        let phrase: String
        /// Spoken form of `label` for VoiceOver, which should not have to
        /// read a tracked all-caps fragment.
        let spoken: String

        var id: Int { days ?? 0 }

        /// The window a clip has to be older than. Nil = no window.
        var maximumAge: TimeInterval? {
            days.map { TimeInterval($0) * 24 * 60 * 60 }
        }
    }

    /// Offered most conservative first: the leading row deletes the fewest
    /// clips, and each row below it strictly includes the one above. Reading
    /// order is therefore also increasing destructiveness, which is the order
    /// a destructive control should be read in.
    static let cutoffs: [Cutoff] = [
        Cutoff(days: 365, label: "A YEAR", phrase: "filmed more than a year ago",
               spoken: "a year"),
        Cutoff(days: 90, label: "90 DAYS", phrase: "filmed more than 90 days ago",
               spoken: "90 days"),
        Cutoff(days: 30, label: "30 DAYS", phrase: "filmed more than 30 days ago",
               spoken: "30 days"),
        Cutoff(days: nil, label: "ANY AGE", phrase: "from every saved swim, whatever its age",
               spoken: "any age"),
    ]

    // MARK: - Results

    /// Exactly what a delete at one cutoff would remove.
    ///
    /// Carries file names rather than a predicate so the caller deletes the
    /// same set the UI priced — the count and the byte total the user agreed
    /// to are the count and the byte total that go.
    struct Selection: Equatable, Identifiable {
        let cutoff: Cutoff
        /// Oldest first, then by name — deterministic, so the log and the
        /// tests read the same order every run.
        let fileNames: [String]
        let byteCount: Int64

        var id: Int { cutoff.id }
        var count: Int { fileNames.count }
        var isEmpty: Bool { fileNames.isEmpty }
    }

    /// The store, priced and split into the two populations the user can tell
    /// apart: clips their saved swims still point at, and clips nothing has
    /// scored yet.
    struct Summary: Equatable {
        let totalByteCount: Int64
        let fileCount: Int
        /// Claimed by a saved session — the only population this screen deletes.
        let sessionClipCount: Int
        let sessionClipByteCount: Int64
        /// Everything else in the store: unfinished takes, and any debris the
        /// launch sweep has not reached yet. Counted so the headline total
        /// reconciles with the store, never deleted from here.
        let unscoredCount: Int
        let unscoredByteCount: Int64
        /// One entry per `cutoffs` element, in the same order.
        let offers: [Selection]

        static let empty = Summary(totalByteCount: 0, fileCount: 0,
                                   sessionClipCount: 0, sessionClipByteCount: 0,
                                   unscoredCount: 0, unscoredByteCount: 0,
                                   offers: [])

        var isEmpty: Bool { fileCount == 0 }

        /// Is there anything at all this control could delete? False whenever
        /// no saved session has a stored clip — in which case the control must
        /// not appear, because every button on it would delete nothing.
        var hasDeletableClips: Bool { offers.contains { !$0.isEmpty } }

        func offer(for cutoff: Cutoff) -> Selection {
            offers.first { $0.cutoff == cutoff }
                ?? Selection(cutoff: cutoff, fileNames: [], byteCount: 0)
        }

        /// The safe default: the most conservative offer that would actually
        /// free something. Nil when nothing is deletable.
        var defaultCutoff: Cutoff? { offers.first { !$0.isEmpty }?.cutoff }
    }

    // MARK: - Decisions

    /// Price the store and build every offer in one pass.
    static func summarize(files: [UnfinishedTakes.StoredFile],
                          referencedIDs: Set<String>,
                          now: Date = Date()) -> Summary {
        let claimed = sessionClips(among: files, referencedIDs: referencedIDs)
        let claimedNames = Set(claimed.map(\.name))
        let unscored = files.filter { !claimedNames.contains($0.name) }

        return Summary(
            totalByteCount: totalBytes(files),
            fileCount: files.count,
            sessionClipCount: claimed.count,
            sessionClipByteCount: totalBytes(claimed),
            unscoredCount: unscored.count,
            unscoredByteCount: totalBytes(unscored),
            offers: cutoffs.map { cutoff in
                selection(sessionClips: claimed, olderThan: cutoff, now: now)
            })
    }

    /// The clips a delete at `cutoff` would remove.
    static func selection(files: [UnfinishedTakes.StoredFile],
                          referencedIDs: Set<String>,
                          olderThan cutoff: Cutoff,
                          now: Date = Date()) -> Selection {
        selection(sessionClips: sessionClips(among: files, referencedIDs: referencedIDs),
                  olderThan: cutoff, now: now)
    }

    // MARK: - Helpers

    private static func selection(sessionClips: [UnfinishedTakes.StoredFile],
                                  olderThan cutoff: Cutoff,
                                  now: Date) -> Selection {
        let candidates = sessionClips
            .filter { isOlder($0, than: cutoff, now: now) }
            .sorted {
                $0.modifiedAt == $1.modifiedAt
                    ? $0.name < $1.name
                    : $0.modifiedAt < $1.modifiedAt
            }
        return Selection(cutoff: cutoff,
                         fileNames: candidates.map(\.name),
                         byteCount: totalBytes(candidates))
    }

    /// The names in `fileNames` that a saved session still claims.
    ///
    /// The single gate every deletion in this feature passes through, and it
    /// uses the sweeper's own definition of claimed rather than a second one —
    /// `orphanedFileNames` is what decides that a saved session's video is
    /// untouchable, and a divergence between the two would be a delete path
    /// that disagrees with the invariant it has to respect.
    static func claimedNames(among fileNames: [String],
                             referencedIDs: Set<String>) -> [String] {
        let unclaimed = Set(SessionVideoStore.orphanedFileNames(
            among: fileNames, referencedIDs: referencedIDs))
        return fileNames.filter { !unclaimed.contains($0) }
    }

    private static func sessionClips(among files: [UnfinishedTakes.StoredFile],
                                     referencedIDs: Set<String>) -> [UnfinishedTakes.StoredFile] {
        let claimed = Set(claimedNames(among: files.map(\.name), referencedIDs: referencedIDs))
        return files.filter { claimed.contains($0.name) }
    }

    /// Strictly older. A clip filmed exactly 30 days ago is not yet "older
    /// than 30 days", and `UnfinishedTakes` draws its own boundary the same
    /// way (`age <= retention` is still inside the window) — one convention,
    /// and it errs toward keeping the file.
    ///
    /// A clock that jumped forward can make a fresh clip look old; a clock
    /// that jumped back makes `age` negative, which fails the comparison and
    /// keeps the clip. Keeping is the safe direction, so no special case.
    private static func isOlder(_ file: UnfinishedTakes.StoredFile,
                                than cutoff: Cutoff,
                                now: Date) -> Bool {
        guard let maximumAge = cutoff.maximumAge else { return true }
        return now.timeIntervalSince(file.modifiedAt) > maximumAge
    }

    private static func totalBytes(_ files: [UnfinishedTakes.StoredFile]) -> Int64 {
        files.reduce(0) { $0 + $1.byteCount }
    }

    // MARK: - Formatting

    /// Base-10 file sizes, the same convention `TakeCard` shows and iOS
    /// Settings reports storage in — a number the user can compare against
    /// what their phone tells them, rather than a second definition of "MB".
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter
    }()

    static func sizeText(_ byteCount: Int64) -> String {
        byteFormatter.string(fromByteCount: byteCount)
    }

    static func clipCountText(_ count: Int) -> String {
        "\(count) clip\(count == 1 ? "" : "s")"
    }
}
