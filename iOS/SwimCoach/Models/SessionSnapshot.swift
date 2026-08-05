import Foundation

/// Plain-value copy of the `SwimSession` scalars the training-log exports
/// read.
///
/// SwiftData `@Model` types are reference types tied to the `ModelContext`
/// that vended them — `@Query` results belong to the main actor's context,
/// and reading their properties from another thread is a race (property
/// access goes through the context, and `resultData` is
/// `.externalStorage`, so it can fault in from disk on first touch). Export
/// therefore captures everything it needs here, synchronously on the actor
/// that owns the models, and hands these `Sendable` values to the
/// background builder. Nothing that crosses the isolation boundary keeps a
/// reference to a model or its context.
///
/// The capture initializer is deliberately *not* `@MainActor`: it is the
/// caller's job to be on the model's actor (see `AboutView`), and pinning
/// it to the main actor would make it uncallable from the unit tests that
/// build models on the test thread.
struct SessionSnapshot: Sendable, Equatable {
    let analyzedAt: Date
    let name: String
    let swimmer: String
    let notes: String
    let score: Int
    let grade: String
    let issueNames: [String]
    let strokeCount: Int
    let kickRatePerMin: Double
    /// The denormalized clip length; 0 is its "unknown" sentinel.
    let durationSeconds: Double
    /// Clip length recovered from the result blob, populated only for the
    /// pre-v1.43.0 rows whose `durationSeconds` column is unset. Decoding
    /// eagerly for every row would undo the blob-decode removal from
    /// v1.45.5, so the sentinel check happens here rather than later.
    let legacyDurationSeconds: Double?

    /// Captures a model. Call on the actor that owns `session`'s context.
    init(session: SwimSession) {
        self.analyzedAt = session.analyzedAt
        self.name = session.name
        self.swimmer = session.swimmer
        self.notes = session.notes
        self.score = session.score
        self.grade = session.grade
        self.issueNames = session.issueNames
        self.strokeCount = session.strokeCount
        self.kickRatePerMin = session.kickRatePerMin
        self.durationSeconds = session.durationSeconds
        self.legacyDurationSeconds =
            session.durationSeconds > 0 ? nil : session.decoded()?.durationSeconds
    }

    init(analyzedAt: Date, name: String = "", swimmer: String = "", notes: String = "",
         score: Int, grade: String, issueNames: [String] = [], strokeCount: Int,
         kickRatePerMin: Double, durationSeconds: Double = 0,
         legacyDurationSeconds: Double? = nil) {
        self.analyzedAt = analyzedAt
        self.name = name
        self.swimmer = swimmer
        self.notes = notes
        self.score = score
        self.grade = grade
        self.issueNames = issueNames
        self.strokeCount = strokeCount
        self.kickRatePerMin = kickRatePerMin
        self.durationSeconds = durationSeconds
        self.legacyDurationSeconds = legacyDurationSeconds
    }
}

/// Plain-value copy of a `DrillPracticeEvent` — same rationale as
/// `SessionSnapshot`.
struct PracticeSnapshot: Sendable, Equatable {
    let date: Date
    let drillID: String

    /// Captures a model. Call on the actor that owns `event`'s context.
    init(event: DrillPracticeEvent) {
        self.date = event.date
        self.drillID = event.drillID
    }

    init(date: Date, drillID: String) {
        self.date = date
        self.drillID = drillID
    }
}
