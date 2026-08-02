import UIKit

/// Thin fire-and-forget haptics layer. Feedback moments only — never
/// decoration: record start/stop, analysis done, personal best.
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
