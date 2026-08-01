import Foundation

struct TechniqueIssue: Hashable, Codable, Sendable {
    let name: String
    let displayName: String
    let severity: Severity
    let observedValue: Double
    let threshold: Double
    let description: String
    let tip: String

    enum Severity: String, Codable, Comparable, Sendable {
        case minor, moderate, major

        var color: String {
            switch self {
            case .minor: return "yellow"
            case .moderate: return "orange"
            case .major: return "red"
            }
        }

        var icon: String {
            switch self {
            case .minor: return "exclamationmark.circle"
            case .moderate: return "exclamationmark.triangle"
            case .major: return "xmark.octagon"
            }
        }

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            let order: [Severity: Int] = [.minor: 0, .moderate: 1, .major: 2]
            return order[lhs, default: 0] < order[rhs, default: 0]
        }
    }
}
