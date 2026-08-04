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
// its analysis will produce, and `pruneOrphans` is the single garbage
// collector — a clip the user retakes or abandons is either discarded
// explicitly or swept at the next launch.
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

    /// Drop a clip the user rejected (Retake) or walked away from without a
    /// saved session. Only ever removes files inside the session store, so
    /// calling it on a bundled or photo-library clip is a no-op.
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
    /// Membership is decided on the file's basename against session ids —
    /// never by decoding `SwimSession.resultData`, whose externally-stored
    /// keypoint blob costs a disk read plus a full JSON pass per session and
    /// carries nothing this needs. Pure so the sweep is testable without disk.
    static func orphanedFileNames(among fileNames: [String],
                                  referencedIDs: Set<String>) -> [String] {
        fileNames.filter { !referencedIDs.contains(($0 as NSString).deletingPathExtension) }
    }

    /// Delete stored videos no session references any more — keeps the
    /// session store from growing unbounded when a clip is abandoned mid-flow
    /// or a deletion misses its file.
    ///
    /// Runs once per launch (see `RootView`), which is the only window where
    /// no clip can be mid-flight: a clip adopted during this launch is still
    /// unreferenced until its session saves, and sweeping then would delete
    /// the video out from under a running analysis.
    static func pruneOrphans(referencedIDs: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return }
        let orphans = orphanedFileNames(among: files.map(\.lastPathComponent),
                                        referencedIDs: referencedIDs)
        for name in orphans {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            AppLog.storage.info("Pruned orphan session video: \(name)")
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

    // MARK: - Helpers

    /// Is this URL a file the store itself owns?
    private static func isStored(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL
    }
}
