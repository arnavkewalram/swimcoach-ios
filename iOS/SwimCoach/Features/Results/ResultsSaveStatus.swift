import Foundation

/// What the Results footer says about persistence.
///
/// Three states, not two: an unsaved result is either a failed save or a
/// sample swim, and only one of those is an error. `AnalyzingView` skips the
/// save for bundled samples on purpose, so reading "not in the store" as
/// "storage error" told everyone who tried a sample — App Review first among
/// them — that the app had just failed.
enum ResultsSaveStatus: Equatable {
    case saved
    case sample
    case failed

    init(isSaved: Bool, isSample: Bool) {
        if isSaved {
            self = .saved
        } else if isSample {
            self = .sample
        } else {
            self = .failed
        }
    }

    var message: String {
        switch self {
        case .saved: return "Session saved"
        case .sample: return "Sample swim — not saved to your history"
        case .failed: return "Session not saved — a storage error occurred"
        }
    }

    var symbolName: String {
        switch self {
        case .saved: return "checkmark"
        case .sample: return "info.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    var isError: Bool { self == .failed }
}
