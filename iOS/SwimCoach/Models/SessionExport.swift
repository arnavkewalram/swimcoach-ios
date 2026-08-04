import Foundation

/// Compact, human-readable training-log export — the journal without the
/// heavyweight keypoint/video payloads. Pure encoding — unit-tested.
enum SessionExport {

    struct ExportedSession: Codable, Equatable {
        let date: Date
        let name: String
        let notes: String
        let score: Int
        let grade: String
        let strokeCount: Int
        let kickRatePerMin: Double
        let issues: [String]
    }

    struct ExportedPractice: Codable, Equatable {
        let date: Date
        let drill: String
    }

    struct Archive: Codable, Equatable {
        let app: String
        let exportedAt: Date
        let sessions: [ExportedSession]
        var practice: [ExportedPractice]? = nil
    }

    /// Chronological (oldest first) JSON archive of the training log.
    /// Captures the models on the caller's actor, then encodes from the
    /// snapshots — identical bytes to encoding from the models directly.
    static func archiveData(from sessions: [SwimSession],
                            practice: [DrillPracticeEvent] = [],
                            now: Date = Date()) throws -> Data {
        try archiveData(snapshots: sessions.map { SessionSnapshot(session: $0) },
                        practice: practice.map { PracticeSnapshot(event: $0) },
                        now: now)
    }

    /// The encoding path. Takes `Sendable` values so a background task can
    /// run it without touching a `ModelContext`.
    static func archiveData(snapshots: [SessionSnapshot],
                            practice: [PracticeSnapshot] = [],
                            now: Date = Date()) throws -> Data {
        let exported = snapshots
            .sorted { $0.analyzedAt < $1.analyzedAt }
            .map { s in
                ExportedSession(
                    date: s.analyzedAt,
                    name: s.name,
                    notes: s.notes,
                    score: s.score,
                    grade: s.grade,
                    strokeCount: s.strokeCount,
                    kickRatePerMin: s.kickRatePerMin,
                    issues: s.issueNames)
            }
        let exportedPractice = practice
            .sorted { $0.date < $1.date }
            .map { ExportedPractice(date: $0.date, drill: $0.drillID) }
        let archive = Archive(app: "SwimCoach", exportedAt: now, sessions: exported,
                              practice: exportedPractice.isEmpty ? nil : exportedPractice)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }
}
