import Foundation

/// Retention policy for clips the store adopted but no session ever claimed.
///
/// `SessionVideoStore.adopt` takes ownership of a capture the moment filming
/// stops, long before an analysis exists to claim it. Every route that then
/// fails to produce a saved session — a rejected clip, a mid-run error, a user
/// who walks away — leaves that file behind with a name no `SwimSession.id`
/// matches. The launch sweep used to delete all of them on sight, so a lap the
/// user actually filmed could vanish before they ever saw it offered back.
///
/// This is the pure decision that separates the two populations. It is a
/// classification, not a deletion: `takes` is what the recovery screen lists,
/// `expired` is what the sweeper is allowed to remove, and a file referenced by
/// a saved session appears in neither — the invariant that a claimed session's
/// video is never deleted is enforced here, before any FileManager call.
enum UnfinishedTakes {

    /// How long an unclaimed clip is held before the sweeper takes it.
    ///
    /// Seven days, matching the unit the rest of the app already reasons in:
    /// weekly goals, weekly streaks, sessions-per-week. The failure this
    /// window exists to cover is "filmed a lap, analysis died, came back at
    /// the next practice" — a swimmer whose training week is the natural
    /// return interval must find the take still waiting. Anything much
    /// shorter (24–48h) re-opens exactly the bug this closes for anyone who
    /// films on a weekend and reopens the app mid-week. Anything much longer
    /// is dead weight: these are tens of megabytes each, and a take nobody
    /// recovered inside a full training week is one they have forgotten about.
    static let retention: TimeInterval = 7 * 24 * 60 * 60

    /// A directory entry as the sweeper sees it.
    ///
    /// Deliberately not a `URL`: the age decision has to be testable without
    /// touching a filesystem, so the caller reads the attributes and this type
    /// carries only what the decision needs.
    struct StoredFile: Hashable {
        /// Basename plus extension, e.g. `<uuid>.mov`.
        let name: String
        /// When the bytes last changed. `adopt` moves the capture within the
        /// same volume, which is a rename — the recording's own timestamp
        /// survives it, so this really is when the lap was filmed.
        let modifiedAt: Date
        let byteCount: Int64

        init(name: String, modifiedAt: Date, byteCount: Int64 = 0) {
            self.name = name
            self.modifiedAt = modifiedAt
            self.byteCount = byteCount
        }
    }

    /// An unclaimed clip still inside its retention window.
    struct Take: Identifiable, Hashable {
        /// The id the file is named after — and the id a re-analysis must
        /// carry, so that the `<result-id>.<ext>` invariant survives the
        /// second pass and the recovered take is not orphaned all over again.
        let id: UUID
        let fileName: String
        let capturedAt: Date
        let byteCount: Int64
    }

    /// Everything unclaimed in the store, split by what may still be wanted.
    struct Classification: Equatable {
        /// Recoverable takes, newest first.
        let takes: [Take]
        /// File names the sweeper may delete: past the window, or never
        /// recoverable in the first place.
        let expired: [String]
    }

    /// Split the store's contents into claimed (absent from both lists),
    /// recoverable, and expired.
    ///
    /// Three rules, in order:
    /// 1. A file whose basename is a saved session's id is claimed. It is
    ///    never listed and never expired — no window, no exceptions.
    /// 2. An unclaimed file named after a UUID is a take. It is recoverable
    ///    while `now - modifiedAt <= retention`, expired after.
    /// 3. Anything else in the directory is debris (`.DS_Store`, a legacy
    ///    name, a half-written temp file). Nothing has ever written a
    ///    non-id name into the store, so it expires immediately rather than
    ///    being offered to the user as a swim.
    static func classify(files: [StoredFile],
                         referencedIDs: Set<String>,
                         now: Date = Date(),
                         retention: TimeInterval = retention) -> Classification {
        // One definition of "claimed", shared with the sweeper's own
        // set-membership derivation.
        let unclaimed = Set(SessionVideoStore.orphanedFileNames(
            among: files.map(\.name), referencedIDs: referencedIDs))

        var takes: [Take] = []
        var expired: [String] = []
        for file in files where unclaimed.contains(file.name) {
            // A clock that jumped backwards makes `age` negative; retaining is
            // the safe direction, so only a genuinely old file expires.
            guard let id = UUID(uuidString: (file.name as NSString).deletingPathExtension),
                  now.timeIntervalSince(file.modifiedAt) <= retention else {
                expired.append(file.name)
                continue
            }
            takes.append(Take(id: id,
                              fileName: file.name,
                              capturedAt: file.modifiedAt,
                              byteCount: file.byteCount))
        }

        // Newest first, with the name as tie-break so two takes filmed inside
        // the same filesystem timestamp still order deterministically.
        takes.sort {
            $0.capturedAt == $1.capturedAt
                ? $0.fileName < $1.fileName
                : $0.capturedAt > $1.capturedAt
        }
        return Classification(takes: takes, expired: expired)
    }
}
