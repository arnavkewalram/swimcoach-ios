import XCTest
@testable import SwimCoach

/// The failure-kind → recovery-action mapping is the analysis-failure screen's
/// only way out: `.navigationBarHidden(true)` removes the system Back button
/// and CANCEL exists only while the analysis is still running.
///
/// The load-bearing rule is that a footage rejection must NOT offer "Try
/// again" — `videoURL` is immutable, so re-running the same clip reproduces
/// the same rejection while the copy is telling the user to go re-film.
final class AnalysisFailureTests: XCTestCase {

    private let allKinds: [AnalysisFailureKind] = [.footageRejected, .transient]

    // MARK: - Kind → actions

    func testFootageRejectionOffersNoTryAgain() {
        XCTAssertFalse(AnalysisFailureKind.footageRejected.actions.contains(.tryAgain),
                       "Retrying a rejected clip can only fail the same way")
    }

    func testFootageRejectionOffersRecordAgainThenHome() {
        XCTAssertEqual(AnalysisFailureKind.footageRejected.actions,
                       [.recordAgain, .backToHome])
    }

    func testTransientFailureOffersTryAgain() {
        XCTAssertTrue(AnalysisFailureKind.transient.actions.contains(.tryAgain))
    }

    func testTransientFailureLeadsWithTryAgain() {
        XCTAssertEqual(AnalysisFailureKind.transient.actions.first, .tryAgain,
                       "A mid-run error is worth retrying before re-filming")
    }

    func testEveryFailureKindCanReachCameraAndHome() {
        for kind in allKinds {
            XCTAssertTrue(kind.actions.contains(.recordAgain), "\(kind) cannot reach the camera")
            XCTAssertTrue(kind.actions.contains(.backToHome), "\(kind) cannot reach Home")
        }
    }

    func testNoFailureKindRepeatsAnAction() {
        for kind in allKinds {
            XCTAssertEqual(Set(kind.actions).count, kind.actions.count, "\(kind) has duplicates")
        }
    }

    // MARK: - Pipeline failure sites → kind

    func testNoSwimmerDetectedIsAFootageRejection() {
        let failure = AnalysisFailure.noSwimmerDetected
        XCTAssertEqual(failure.kind, .footageRejected)
        XCTAssertFalse(failure.actions.contains(.tryAgain))
        XCTAssertTrue(failure.message.contains("No horizontal swimmer detected"))
    }

    func testTooFewFramesIsAFootageRejectionAndReportsTheCount() {
        let failure = AnalysisFailure.tooFewFrames(4)
        XCTAssertEqual(failure.kind, .footageRejected)
        XCTAssertFalse(failure.actions.contains(.tryAgain))
        XCTAssertTrue(failure.message.contains("(4)"), failure.message)
    }

    func testUnusablePosesIsAFootageRejection() {
        let failure = AnalysisFailure.unusablePoses
        XCTAssertEqual(failure.kind, .footageRejected)
        XCTAssertFalse(failure.actions.contains(.tryAgain))
    }

    func testUnexpectedErrorIsTransientAndKeepsTryAgain() {
        struct Boom: LocalizedError {
            var errorDescription: String? { "model failed to load" }
        }
        let failure = AnalysisFailure.unexpected(Boom())
        XCTAssertEqual(failure.kind, .transient)
        XCTAssertTrue(failure.actions.contains(.tryAgain))
        XCTAssertEqual(failure.message, "model failed to load")
    }

    /// The re-film advice only makes sense if the screen can reach the camera.
    func testFootageRejectionsAdviseRefilmingAndOfferTheCamera() {
        let refilmFailures: [AnalysisFailure] = [
            .noSwimmerDetected, .tooFewFrames(2), .unusablePoses,
        ]
        for failure in refilmFailures {
            XCTAssertTrue(failure.actions.contains(.recordAgain), failure.message)
            XCTAssertEqual(failure.actions.first, .recordAgain, failure.message)
        }
    }

    /// A file with no video track cannot grow one between attempts, so the
    /// screen must stop offering a retry that can only fail the same way.
    func testMissingVideoTrackIsAFootageRejectionNotATransientError() {
        let failure = AnalysisFailure.unexpected(AnalysisError.noVideoTrack)
        XCTAssertEqual(failure.kind, .footageRejected)
        XCTAssertFalse(failure.actions.contains(.tryAgain))
        XCTAssertTrue(failure.actions.contains(.recordAgain))
    }

    /// `startReading()` also fails under momentary resource pressure, so this
    /// one keeps the retry — a wasted tap is cheaper than a wasted re-film.
    func testReaderFailureStaysTransient() {
        let failure = AnalysisFailure.unexpected(AnalysisError.readerFailed("disk busy"))
        XCTAssertEqual(failure.kind, .transient)
        XCTAssertTrue(failure.actions.contains(.tryAgain))
    }

    // MARK: - Guidance

    private var allFailures: [AnalysisFailure] {
        struct Boom: LocalizedError { var errorDescription: String? { "inference failed" } }
        return [
            .noSwimmerDetected, .tooFewFrames(3), .unusablePoses,
            .unexpected(AnalysisError.noVideoTrack), .unexpected(Boom()),
        ]
    }

    func testEveryFailureCarriesActionableGuidance() {
        for failure in allFailures {
            XCTAssertFalse(failure.checklist.isEmpty, failure.message)
            XCTAssertFalse(failure.checklistTitle.isEmpty, failure.message)
            for item in failure.checklist {
                XCTAssertFalse(item.trimmingCharacters(in: .whitespaces).isEmpty, failure.message)
            }
        }
    }

    /// Advice belongs in the checklist, not stapled onto the end of the
    /// diagnosis — the message is rendered as a single body-tier line.
    func testDiagnosisMessagesStayShortAndSingleLine() {
        for failure in allFailures {
            XCTAssertFalse(failure.message.contains("\n"), failure.message)
            XCTAssertLessThanOrEqual(failure.message.count, 100, failure.message)
        }
    }

    func testChecklistItemsAreDistinctWithinAFailure() {
        for failure in allFailures {
            XCTAssertEqual(Set(failure.checklist).count, failure.checklist.count, failure.message)
        }
    }

    // MARK: - Action presentation

    func testExactlyOneActionPerKindIsPrimary() {
        for kind in allKinds {
            let primaries = kind.actions.filter { kind.tier(for: $0) == .primary }
            XCTAssertEqual(primaries, [kind.actions[0]], "\(kind) must lead with exactly one primary")
        }
    }

    /// The escape hatch must never be drawn as loudly as the next-best move.
    func testBackToHomeIsAlwaysTertiary() {
        for kind in allKinds {
            XCTAssertEqual(kind.tier(for: .backToHome), .tertiary, "\(kind)")
        }
    }

    func testTransientMiddleActionIsSecondary() {
        XCTAssertEqual(AnalysisFailureKind.transient.tier(for: .recordAgain), .secondary)
        XCTAssertEqual(AnalysisFailureKind.footageRejected.tier(for: .recordAgain), .primary)
    }

    func testEveryKindHasADistinctStamp() {
        let stamps = allKinds.map(\.stamp)
        XCTAssertEqual(Set(stamps).count, stamps.count)
        for stamp in stamps {
            XCTAssertFalse(stamp.isEmpty)
            XCTAssertEqual(stamp, stamp.uppercased(), "Stamps are a caps register mark")
        }
    }

    func testActionTitlesAreDistinctAndNonEmpty() {
        let actions: [AnalysisFailureAction] = [.tryAgain, .recordAgain, .backToHome]
        let titles = actions.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
        for action in actions {
            XCTAssertFalse(action.title.isEmpty)
            XCTAssertFalse(action.accessibilityLabel.isEmpty)
        }
    }
}
