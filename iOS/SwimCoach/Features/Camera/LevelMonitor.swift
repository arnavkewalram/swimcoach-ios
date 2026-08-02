import CoreMotion
import Foundation

/// Roll math for the camera level indicator. Pure — unit-tested.
enum LevelMath {
    /// Device roll in degrees for portrait orientation, from the gravity
    /// vector. 0° = level; positive = top of phone tilted right.
    static func rollDegrees(gravityX: Double, gravityY: Double) -> Double {
        atan2(gravityX, -gravityY) * 180 / .pi
    }

    static func isLevel(_ roll: Double, tolerance: Double = 2.0) -> Bool {
        abs(roll) <= tolerance
    }
}

/// Publishes device roll while the camera is open. `rollDegrees` stays nil
/// when motion data is unavailable (e.g. the simulator) so the indicator
/// simply doesn't render.
final class LevelMonitor: ObservableObject {
    @Published private(set) var rollDegrees: Double? = nil
    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 15.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let g = motion?.gravity else { return }
            self?.rollDegrees = LevelMath.rollDegrees(gravityX: g.x, gravityY: g.y)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        rollDegrees = nil
    }
}
