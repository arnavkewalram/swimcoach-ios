import Foundation

/// Builds the training-log export files off the main thread.
///
/// Both entry points are nonisolated `async`, so a `@MainActor` caller's
/// `await` leaves the main actor (SE-0338) and the string building, JSON
/// encoding, and file write all happen on the cooperative pool. They accept
/// only `Sendable` snapshots — never `@Model` objects, which belong to their
/// `ModelContext`'s actor and would race if read here. Capture the snapshots
/// on the model's actor first (`SessionSnapshot`).
enum TrainingLogWriter {

    static let archiveFilename = "swimcoach-training-log.json"
    static let csvFilename = "swimcoach-training-log.csv"

    /// Writes the JSON archive to a temp file and returns its URL.
    static func writeArchive(sessions: [SessionSnapshot],
                             practice: [PracticeSnapshot]) async throws -> URL {
        let data = try SessionExport.archiveData(snapshots: sessions, practice: practice)
        return try write(data, named: archiveFilename)
    }

    /// Writes the CSV spreadsheet to a temp file and returns its URL.
    static func writeCSV(sessions: [SessionSnapshot]) async throws -> URL {
        let csv = SessionCSV.csv(snapshots: sessions)
        return try write(Data(csv.utf8), named: csvFilename)
    }

    private static func write(_ data: Data, named filename: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }
}
