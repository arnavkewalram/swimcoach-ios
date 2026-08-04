import SwiftUI
import XCTest
@testable import SwimCoach

/// Stack shape for the record → review → retake loop.
///
/// `NavigationPath` is type-erased: nothing can read back *which* screens are
/// on it, so a navigation action that leaves the wrong stack is invisible in
/// code review and only shows up on device as a screen that will not go away.
/// Retake used to call `replaceTop(with: .camera)` from a `[camera, review]`
/// stack — dropping `review` and appending a SECOND camera, then a third, one
/// per cycle. Depth is the one property that is observable, and it is enough
/// to pin that.
@MainActor
final class AppRouterTests: XCTestCase {

    private func clip() -> PendingClip {
        PendingClip(external: URL(fileURLWithPath: "/tmp/take.mov"))
    }

    /// The live stack while Review is on screen: Home pushes `.camera`, and
    /// `CameraView` pushes `.review` when recording stops.
    private func recordedTakeStack() -> AppRouter {
        let router = AppRouter()
        router.push(.camera)
        router.push(.review(clip()))
        return router
    }

    /// The DEBUG `-demoReview` stack: Home pushes `.review` straight from the
    /// root, so there is no camera underneath.
    private func demoReviewStack() -> AppRouter {
        let router = AppRouter()
        router.push(.review(clip()))
        return router
    }

    // MARK: - Retake

    /// The regression test. Against the old `replaceTop(with: .camera)` this
    /// path holds two entries — `[camera, camera]`.
    func testRetakeAfterRecordingLeavesExactlyOneScreen() {
        // Arrange
        let router = recordedTakeStack()
        XCTAssertEqual(router.path.count, 2, "Review sits on top of the camera")

        // Act
        ReviewView.routeToRetake(router)

        // Assert
        XCTAssertEqual(router.path.count, 1,
                       "Retake must return to the one camera already on the stack, "
                       + "not push a second one on top of it")
    }

    /// Rejecting take after take is the whole point of the screen; the stack
    /// must not record the history of that indecision.
    func testRepeatedRecordRetakeCyclesDoNotGrowTheStack() {
        // Arrange
        let router = AppRouter()
        router.push(.camera)

        // Act — five record → review → retake rounds
        for _ in 0..<5 {
            router.push(.review(clip()))       // recording stopped
            ReviewView.routeToRetake(router)   // "Retake"
        }

        // Assert
        XCTAssertEqual(router.path.count, 1,
                       "Every cycle must land back on a single camera")
    }

    /// The DEBUG `-demoReview` route opens Review from the root, so popToRoot
    /// clears an empty-below stack rather than a camera. Same destination,
    /// same depth.
    func testRetakeFromDemoReviewRouteAlsoLeavesOneCamera() {
        // Arrange
        let router = demoReviewStack()

        // Act
        ReviewView.routeToRetake(router)

        // Assert
        XCTAssertEqual(router.path.count, 1,
                       "Retake from the demo route opens the camera over Home")
    }

    // MARK: - Use this clip

    /// The other exit is a genuine swap: Analyzing takes Review's slot so Back
    /// out of it reaches the camera, and `.analyzing` is never the entry
    /// underneath, so there is nothing to duplicate.
    func testUseThisClipSwapsReviewForAnalyzingWithoutGrowingTheStack() {
        // Arrange
        let router = recordedTakeStack()

        // Act
        ReviewView.routeToAnalysis(router, clip: clip())

        // Assert
        XCTAssertEqual(router.path.count, 2,
                       "Analyzing replaces Review above the camera")
    }

    func testUseThisClipFromDemoReviewRouteStaysOneDeep() {
        // Arrange
        let router = demoReviewStack()

        // Act
        ReviewView.routeToAnalysis(router, clip: clip())

        // Assert
        XCTAssertEqual(router.path.count, 1)
    }

    // MARK: - Router primitives

    /// `popToRoot` is called from screens that may already be at the root
    /// (Home's own launch-argument routes run before anything is pushed), and
    /// `removeLast(0)` on an empty path must not trap.
    func testPopToRootOnEmptyPathIsSafe() {
        // Arrange
        let router = AppRouter()

        // Act
        router.popToRoot()

        // Assert
        XCTAssertTrue(router.path.isEmpty)
    }

    func testPopToRootClearsADeepStack() {
        // Arrange
        let router = AppRouter()
        router.push(.history)
        router.push(.camera)
        router.push(.review(clip()))

        // Act
        router.popToRoot()

        // Assert
        XCTAssertEqual(router.path.count, 0)
    }

    /// `replaceTop` swaps rather than stacks — correct when the destination is
    /// new to the stack, which is exactly the assumption Retake violated.
    func testReplaceTopKeepsDepthConstant() {
        // Arrange
        let router = AppRouter()
        router.push(.camera)
        router.push(.review(clip()))

        // Act
        router.replaceTop(with: .analyzing(clip()))

        // Assert
        XCTAssertEqual(router.path.count, 2)
    }

    /// On an empty path there is no top to replace, so it degrades to a push.
    func testReplaceTopOnEmptyPathPushes() {
        // Arrange
        let router = AppRouter()

        // Act
        router.replaceTop(with: .camera)

        // Assert
        XCTAssertEqual(router.path.count, 1)
    }
}
