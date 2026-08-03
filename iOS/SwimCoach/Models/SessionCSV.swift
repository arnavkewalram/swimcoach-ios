import Foundation

/// Spreadsheet-friendly view of the training log — one header row plus one
/// row per session, newest first (matching the History list). Pure string
/// building — unit-tested. Heavyweight payloads (keypoints, windows) stay
/// out; only durationSeconds needs the stored result blob.
enum SessionCSV {

    static let header =
        "date,name,swimmer,score,grade,issues,strokeCount,kickRatePerMin,durationSeconds"

    /// RFC 4180-style CSV of the session history, newest session first.
    static func csv(from sessions: [SwimSession]) -> String {
        let rows = sessions
            .sorted { $0.analyzedAt > $1.analyzedAt }
            .map { row(for: $0) }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    private static func row(for session: SwimSession) -> String {
        // Legacy sessions (pre-stroke-rate) have no duration — empty field.
        let duration = session.decoded()?.durationSeconds
        return [
            session.analyzedAt.formatted(.iso8601),
            escape(session.name),
            escape(session.swimmer),
            String(session.score),
            escape(session.grade),
            escape(session.issueNames.joined(separator: "; ")),
            String(session.strokeCount),
            number(session.kickRatePerMin),
            duration.map { number($0) } ?? "",
        ].joined(separator: ",")
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

    /// Locale-independent numeric field: up to two decimals with trailing
    /// zeros trimmed ("52.00" → "52", "62.50" → "62.5").
    private static func number(_ value: Double) -> String {
        var text = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
