import Foundation
import SwiftData

/// A clip on its way into analysis, paired with the id its `AnalysisResult`
/// will carry.
///
/// The pairing is the load-bearing part of the whole clip lifecycle.
/// `SessionVideoStore` names every stored file `<result-id>.<ext>` and
/// `pruneOrphans` derives the set of still-referenced files from the cheap
/// `SwimSession.id` column — so a clip persisted *before* analysis only
/// survives the sweeper if the analysis it feeds produces a result with this
/// exact id. `AnalyzingView` therefore uses `clip.id` as its result id rather
/// than minting a fresh one.
struct PendingClip: Hashable {
    /// Doubles as the stored file's basename and as the future result id.
    let id: UUID
    /// Where the clip is right now: inside the session store once it has
    /// been adopted, otherwise wherever it came from (photo import, bundle).
    let url: URL

    /// A clip from a source the store does not own — photo-library imports,
    /// the bundled demo video, the DEBUG file picker. It still gets its id
    /// up front so the same invariant holds when analysis persists it.
    init(external url: URL) {
        self.init(id: UUID(), url: url)
    }

    init(id: UUID, url: URL) {
        self.id = id
        self.url = url
    }
}

// Persists session videos so Review/Results/History can play them back.
//
// Camera recordings and picked files land in temp directories that iOS
// reclaims, so the store takes ownership as early as it can: a capture is
// *adopted* (moved out of temp) the moment recording stops, before the user
// has even decided to keep it. From then on the file is named after the id
// its analysis will produce.
//
// A clip that never reaches a saved session is NOT garbage on sight. The
// sweeper defers to `UnfinishedTakes`: an unclaimed clip is held for a
// retention window and offered back on Home, and only a genuinely expired one
// is deleted. The single explicit "no" is `discard` — Retake — which still
// removes the file immediately.
//
// Bundled demo videos are resolved from the app bundle instead of being
// copied, so they never appear in `directory` and the sweeper never sees them.
enum SessionVideoStore {

    static var directory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Capture lifecycle

    /// Take ownership of a freshly captured clip: move it out of the volatile
    /// temp directory into the session store under a fresh id, and hand back
    /// the id/url pair the analysis has to carry so the saved session and the
    /// stored file agree on a name.
    ///
    /// Falls back to the original URL when the move fails — a review screen
    /// playing a temp file still beats dropping the take on the floor, and
    /// `persist` will copy it into place if analysis succeeds.
    static func adopt(_ capturedURL: URL) -> PendingClip {
        let id = UUID()
        let ext = capturedURL.pathExtension.isEmpty ? "mov" : capturedURL.pathExtension
        let dest = directory.appendingPathComponent("\(id.uuidString).\(ext)")
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: capturedURL, to: dest)
            return PendingClip(id: id, url: dest)
        } catch {
            AppLog.storage.error("Could not adopt capture: \(error.localizedDescription)")
            return PendingClip(id: id, url: capturedURL)
        }
    }

    /// Drop a clip the user explicitly rejected — Retake, or Delete on the
    /// unfinished-takes screen. This is the only immediate deletion: every
    /// other way of leaving a clip behind hands it to the retention window
    /// instead. Only ever removes files inside the session store, so calling
    /// it on a bundled or photo-library clip is a no-op.
    static func discard(_ clip: PendingClip) {
        guard isStored(clip.url) else { return }
        try? FileManager.default.removeItem(at: clip.url)
        AppLog.storage.info("Discarded unused clip: \(clip.url.lastPathComponent)")
    }

    /// Copy the analyzed video into the session store. Returns the stored
    /// file name, or nil if the copy failed (playback is then simply
    /// unavailable — never fatal to the analysis itself).
    static func persist(_ sourceURL: URL, for id: UUID) -> String? {
        // Already adopted into the store under this id (the camera path) —
        // the file is where it belongs and carries the right name.
        if isStored(sourceURL),
           sourceURL.deletingPathExtension().lastPathComponent == id.uuidString {
            return sourceURL.lastPathComponent
        }
        // Bundled resources don't need copying — reference by name.
        if Bundle.main.url(forResource: sourceURL.deletingPathExtension().lastPathComponent,
                           withExtension: sourceURL.pathExtension) == sourceURL {
            return sourceURL.lastPathComponent
        }
        let ext = sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension
        let name = "\(id.uuidString).\(ext)"
        let dest = directory.appendingPathComponent(name)
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            return name
        } catch {
            AppLog.storage.error("Could not persist video: \(error.localizedDescription)")
            return nil
        }
    }

    /// Resolve a stored file name to a playable URL: session store first,
    /// then the app bundle (demo videos). Nil when the file is gone.
    static func url(forFileName fileName: String?) -> URL? {
        guard let fileName, !fileName.isEmpty else { return nil }
        let stored = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: stored.path) {
            return stored
        }
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        return Bundle.main.url(forResource: base, withExtension: ext.isEmpty ? "mp4" : ext)
    }

    /// Remove a stored video (bundle resources are left alone).
    static func delete(fileName: String?) {
        guard let fileName, !fileName.isEmpty else { return }
        let stored = directory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: stored)
    }

    // MARK: - Orphan sweeping

    /// Which of `fileNames` no longer belong to a saved session.
    ///
    /// Membership only — being unclaimed is no longer a licence to delete.
    /// `UnfinishedTakes.classify` takes this set and splits it by age; a
    /// claimed file never reaches that split at all.
    ///
    /// Membership is decided on the file's basename against session ids —
    /// never by decoding `SwimSession.resultData`, whose externally-stored
    /// keypoint blob costs a disk read plus a full JSON pass per session and
    /// carries nothing this needs. Pure so the sweep is testable without disk.
    static func orphanedFileNames(among fileNames: [String],
                                  referencedIDs: Set<String>) -> [String] {
        fileNames.filter { !referencedIDs.contains(($0 as NSString).deletingPathExtension) }
    }

    /// Delete stored videos that are neither referenced by a session nor still
    /// inside their retention window — keeps the store from growing unbounded
    /// without destroying a lap the user filmed an hour ago.
    ///
    /// Runs once per launch (see `RootView`). That schedule used to be
    /// load-bearing for correctness: a clip adopted during this launch is
    /// unreferenced until its session saves, so a mid-session sweep would have
    /// deleted the video out from under a running analysis. Retention now
    /// makes that impossible — a fresh file is never expired — but the sweep
    /// stays off the hot path anyway.
    static func pruneOrphans(referencedIDs: Set<String>, now: Date = Date()) {
        let expired = UnfinishedTakes.classify(files: storedFiles(),
                                               referencedIDs: referencedIDs,
                                               now: now).expired
        for name in expired {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            AppLog.storage.info("Pruned expired session video: \(name)")
        }
    }

    /// Off-main storage hygiene: fetch the session ids through a context of
    /// its own and sweep. Not actor-isolated, so `await`ing it from the main
    /// actor hops to the cooperative pool rather than blocking a frame.
    static func pruneOrphans(in container: ModelContainer) async {
        let context = ModelContext(container)
        let sessions = (try? context.fetch(FetchDescriptor<SwimSession>())) ?? []
        pruneOrphans(referencedIDs: Set(sessions.map(\.id.uuidString)))
    }

    // MARK: - Unfinished takes

    /// Clips the store adopted that no session ever claimed, still inside
    /// their retention window — newest first. What Home counts and the
    /// recovery screen lists.
    static func unfinishedTakes(referencedIDs: Set<String>,
                                now: Date = Date()) -> [UnfinishedTakes.Take] {
        UnfinishedTakes.classify(files: storedFiles(),
                                 referencedIDs: referencedIDs,
                                 now: now).takes
    }

    /// Hand a recovered take back to analysis.
    ///
    /// Reusing `take.id` rather than minting a fresh one is what keeps the
    /// `<result-id>.<ext>` invariant intact across the second pass: the file
    /// is already in the store under this name, so `persist` recognises it and
    /// skips the copy, and the session the analysis saves carries the same id
    /// the file is named after. A fresh id would copy the clip to a second
    /// name and leave the original looking like an orphan.
    static func pendingClip(for take: UnfinishedTakes.Take) -> PendingClip {
        PendingClip(id: take.id, url: directory.appendingPathComponent(take.fileName))
    }

    /// The user said no to this take — delete it now rather than waiting out
    /// the window.
    static func delete(_ take: UnfinishedTakes.Take) {
        delete(fileName: take.fileName)
        AppLog.storage.info("Deleted unfinished take: \(take.fileName)")
    }

    // MARK: - Helpers

    /// The store's contents as the retention decision wants them: name, age
    /// and size, read in one directory pass.
    private static func storedFiles() -> [UnfinishedTakes.StoredFile] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys) else { return [] }
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return UnfinishedTakes.StoredFile(
                name: url.lastPathComponent,
                // No timestamp means the filesystem cannot vouch for the
                // clip's age. `.distantPast` expires it rather than pinning an
                // unaccountable file in the recovery list forever.
                modifiedAt: values?.contentModificationDate ?? .distantPast,
                byteCount: Int64(values?.fileSize ?? 0))
        }
    }

    /// Is this URL a file the store itself owns?
    private static func isStored(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL
    }
}
