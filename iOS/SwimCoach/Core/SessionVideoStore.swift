import Foundation

// Persists analyzed session videos so Results/History can play them back.
// Camera recordings and picked files live in temp directories that iOS
// reclaims — each successful analysis copies its source video into
// Documents/sessions/<result-id>.<ext>. Bundled demo videos are resolved
// from the app bundle instead of being copied.
enum SessionVideoStore {

    static var directory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copy the analyzed video into the session store. Returns the stored
    /// file name, or nil if the copy failed (playback is then simply
    /// unavailable — never fatal to the analysis itself).
    static func persist(_ sourceURL: URL, for id: UUID) -> String? {
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
}
