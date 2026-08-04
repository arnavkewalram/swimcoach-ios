import Foundation

/// Spreadsheet-friendly view of the training log — one header row plus one
/// row per session, newest first (matching the History list). Pure string
/// building — unit-tested. Columns read denormalized `SwimSession` scalars,
/// so a modern row costs no result-blob decode; only rows saved before
/// `durationSeconds` was denormalized (v1.43.0) fall back to the blob, for
/// that one field. That cost is bounded to legacy rows and drops to zero as
/// the library turns over — the same shape as History's common-issues
/// fallback. Unlike a chart, where a missing metric is a meaningful gap,
/// an export is the user's data leaving the app: it never drops a value
/// we demonstrably still hold.
enum SessionCSV {

    static let header =
        "date,name,swimmer,score,grade,issues,strokeCount,kickRatePerMin,durationSeconds"

    /// RFC 4180-style CSV of the session history, newest session first.
    /// Captures the models on the caller's actor, then builds from the
    /// snapshots — identical bytes to building from the models directly.
    static func csv(from sessions: [SwimSession]) -> String {
        csv(snapshots: sessions.map { SessionSnapshot(session: $0) })
    }

    /// The building path. Takes `Sendable` values so a background task can
    /// run it without touching a `ModelContext`.
    static func csv(snapshots: [SessionSnapshot]) -> String {
        let rows = snapshots
            .sorted { $0.analyzedAt > $1.analyzedAt }
            .map { row(for: $0) }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    private static func row(for session: SessionSnapshot) -> String {
        let duration = duration(for: session)
        return [
            session.analyzedAt.formatted(.iso8601),
            escapeUserText(session.name),
            escapeUserText(session.swimmer),
            String(session.score),
            escape(session.grade),
            escapeUserText(session.issueNames.joined(separator: "; ")),
            String(session.strokeCount),
            number(session.kickRatePerMin),
            duration.map { number($0) } ?? "",
        ].joined(separator: ",")
    }

    /// Clip length for the duration column. Reads the denormalized scalar;
    /// 0 is its "unknown" sentinel (`SwimSession.swift`), which pre-v1.43.0
    /// rows migrated in with — those alone fall back to the blob-recovered
    /// duration the snapshot carries (`SessionSnapshot` does that decode,
    /// and only for those rows). `nil` (empty field) only when neither
    /// source has a real positive length, which also collapses NaN and
    /// negative junk, matching `AnalysisResult.durationText`.
    private static func duration(for session: SessionSnapshot) -> Double? {
        if session.durationSeconds > 0 { return session.durationSeconds }
        guard let legacy = session.legacyDurationSeconds, legacy > 0 else { return nil }
        return legacy
    }

    /// RFC 4180 field escaping: quote a field containing a comma, quote,
    /// or line break; double any embedded quotes. Other fields pass through.
    static func escape(_ field: String) -> String {
        let needsQuoting = field.contains { char in
            char == "," || char == "\"" || char == "\n" || char == "\r"
        }
        guard needsQuoting else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    /// Leading characters that Excel/Numbers/Sheets treat as the start of
    /// a formula when a CSV cell begins with them.
    private static let formulaTriggers: Set<Character> = ["=", "+", "-", "@"]

    /// Escaping for user-editable free text (name, swimmer, issue list):
    /// neutralizes spreadsheet formula injection by prefixing a literal
    /// apostrophe when the field starts with `=`, `+`, `-`, or `@`, then
    /// applies the same RFC 4180 quoting as `escape`. Program-generated
    /// numeric columns never pass through here, so negative numbers are
    /// untouched.
    static func escapeUserText(_ field: String) -> String {
        guard let first = field.first, formulaTriggers.contains(first) else {
            return escape(field)
        }
        return escape("'" + field)
    }

    /// Locale-independent numeric field: up to two decimals with trailing
    /// zeros trimmed ("52.00" → "52", "62.50" → "62.5").
    private static func number(_ value: Double) -> String {
        var text = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
