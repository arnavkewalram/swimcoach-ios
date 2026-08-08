import XCTest
import CoreGraphics
@testable import SwimCoach

/// The decisions Compare's side-by-side band rests on, pinned away from any
/// player: how one playhead maps onto two clips of different lengths, what
/// happens when a session has no clip, and how two takes of different
/// orientation share one pane shape.
final class CompareClipsTests: XCTestCase {

    // MARK: - Sync: position mapping

    /// The whole premise: one shared lap position, two different clocks.
    /// Halfway is halfway through each clip, not the same second in both.
    func testSharedPositionMapsToEachClipsOwnTimeline() {
        let map = ClipSyncMap(earlierDuration: 12, laterDuration: 18)
        XCTAssertEqual(map.time(atPosition: 0.5, in: .earlier), 6, accuracy: 0.0001)
        XCTAssertEqual(map.time(atPosition: 0.5, in: .later), 9, accuracy: 0.0001)
        XCTAssertEqual(map.time(atPosition: 1, in: .earlier), 12, accuracy: 0.0001)
        XCTAssertEqual(map.time(atPosition: 1, in: .later), 18, accuracy: 0.0001)
    }

    /// `position(ofTime:)` is what the periodic observer feeds back into the
    /// transport, so it has to be the exact inverse of `time(atPosition:)`.
    func testPositionAndTimeAreInverses() {
        let map = ClipSyncMap(earlierDuration: 12, laterDuration: 18)
        for side in ClipSide.allCases {
            for p in stride(from: 0.0, through: 1.0, by: 0.1) {
                let round = map.position(ofTime: map.time(atPosition: p, in: side), in: side)
                XCTAssertEqual(round, p, accuracy: 0.0001, "\(side) at \(p)")
            }
        }
    }

    /// The follower's own time at a shared position is the length ratio away
    /// from the reference's — the property the drift correction relies on.
    func testTheTwoClipsStayProportionalToEachOther() {
        let map = ClipSyncMap(earlierDuration: 10, laterDuration: 25)
        for p in stride(from: 0.0, through: 1.0, by: 0.25) {
            let earlier = map.time(atPosition: p, in: .earlier)
            let later = map.time(atPosition: p, in: .later)
            XCTAssertEqual(earlier * 2.5, later, accuracy: 0.0001)
        }
    }

    func testPositionsOutsideTheClipAreClamped() {
        let map = ClipSyncMap(earlierDuration: 12, laterDuration: 18)
        XCTAssertEqual(map.time(atPosition: -3, in: .earlier), 0)
        XCTAssertEqual(map.time(atPosition: 4, in: .later), 18)
        XCTAssertEqual(map.position(ofTime: -1, in: .later), 0)
        XCTAssertEqual(map.position(ofTime: 99, in: .later), 1)
    }

    // MARK: - Sync: rates

    /// Rate is the sync mechanism. The longer clip is untouched; the shorter
    /// is slowed by exactly its length ratio so both finish together.
    func testShorterClipIsSlowedToFinishWithTheLongerOne() {
        let map = ClipSyncMap(earlierDuration: 12, laterDuration: 18)
        XCTAssertEqual(map.referenceSide, .later)
        XCTAssertEqual(map.rate(for: .later), 1, accuracy: 0.0001)
        XCTAssertEqual(map.rate(for: .earlier), 12.0 / 18.0, accuracy: 0.0001)
    }

    /// Which side is longer is not fixed — a swimmer's later take is often
    /// the shorter one, and that must not invert the mechanism.
    func testTheLongerSideIsTheReferenceWhicheverItIs() {
        let map = ClipSyncMap(earlierDuration: 20, laterDuration: 8)
        XCTAssertEqual(map.referenceSide, .earlier)
        XCTAssertEqual(map.referenceDuration, 20)
        XCTAssertEqual(map.rate(for: .earlier), 1, accuracy: 0.0001)
        XCTAssertEqual(map.rate(for: .later), 0.4, accuracy: 0.0001)
    }

    /// Nothing is ever played faster than it was swum.
    func testNoClipIsEverSpedUp() {
        for (a, b) in [(3.0, 40.0), (40.0, 3.0), (7.0, 7.0), (0.5, 60.0)] {
            let map = ClipSyncMap(earlierDuration: a, laterDuration: b)
            for side in ClipSide.allCases {
                XCTAssertLessThanOrEqual(map.rate(for: side), 1, "\(a)/\(b) \(side)")
                XCTAssertGreaterThan(map.rate(for: side), 0)
            }
        }
    }

    func testEqualLengthClipsBothRunAtFullRate() {
        let map = ClipSyncMap(earlierDuration: 9, laterDuration: 9)
        XCTAssertEqual(map.rate(for: .earlier), 1, accuracy: 0.0001)
        XCTAssertEqual(map.rate(for: .later), 1, accuracy: 0.0001)
    }

    // MARK: - Sync: degenerate durations

    /// An asset reports `.nan` until it loads and a missing clip has no
    /// duration at all — neither may produce a NaN rate, a NaN playhead, or a
    /// division by zero.
    func testUnloadedAndMissingDurationsBehaveIdentically() {
        for map in [ClipSyncMap(earlierDuration: nil, laterDuration: 18),
                    ClipSyncMap(earlierDuration: .nan, laterDuration: 18),
                    ClipSyncMap(earlierDuration: 0, laterDuration: 18),
                    ClipSyncMap(earlierDuration: -4, laterDuration: 18)] {
            XCTAssertEqual(map.duration(.earlier), 0)
            XCTAssertEqual(map.referenceSide, .later)
            XCTAssertEqual(map.referenceDuration, 18)
            XCTAssertEqual(map.rate(for: .earlier), 1, "a clip that isn't there must not slow to 0")
            XCTAssertEqual(map.time(atPosition: 0.5, in: .earlier), 0)
            XCTAssertEqual(map.position(ofTime: 5, in: .earlier), 0)
            XCTAssertFalse(map.isEmpty)
        }
    }

    func testNoClipsAtAllIsInertRatherThanUndefined() {
        let map = ClipSyncMap(earlierDuration: nil, laterDuration: nil)
        XCTAssertTrue(map.isEmpty)
        XCTAssertEqual(map.referenceDuration, 0)
        XCTAssertEqual(map.rate(for: .earlier), 1)
        XCTAssertEqual(map.positionStep(frames: 1), 0)
        XCTAssertEqual(map.position(0.4, steppedBy: 3), 0.4)
    }

    func testNonFinitePositionsNeverEscapeTheMap() {
        let map = ClipSyncMap(earlierDuration: 12, laterDuration: 18)
        XCTAssertEqual(map.time(atPosition: .nan, in: .later), 0)
        XCTAssertEqual(map.position(ofTime: .nan, in: .later), 0)
        XCTAssertEqual(map.position(.infinity, steppedBy: 1), 0)
    }

    // MARK: - Sync: frame stepping

    /// A nudge moves the reference clip one source frame; the follower moves
    /// the matching fraction of its own, shorter timeline.
    func testAFrameStepMovesTheReferenceByExactlyOneFrame() {
        let map = ClipSyncMap(earlierDuration: 12, laterDuration: 18)
        let stepped = map.position(0.5, steppedBy: 1)
        XCTAssertEqual(map.time(atPosition: stepped, in: .later) - 9,
                       1.0 / 30.0, accuracy: 0.0001)
        XCTAssertEqual(map.time(atPosition: stepped, in: .earlier) - 6,
                       1.0 / 30.0 * (12.0 / 18.0), accuracy: 0.0001)
    }

    func testSteppingStopsAtTheEndsOfTheClip() {
        let map = ClipSyncMap(earlierDuration: 12, laterDuration: 18)
        XCTAssertEqual(map.position(0, steppedBy: -1), 0)
        XCTAssertEqual(map.position(1, steppedBy: 1), 1)
        XCTAssertEqual(map.position(0.5, steppedBy: -1),
                       0.5 - 1.0 / 30.0 / 18.0, accuracy: 0.0001)
    }

    // MARK: - Availability

    private let a = URL(fileURLWithPath: "/tmp/a.mp4")
    private let b = URL(fileURLWithPath: "/tmp/b.mp4")

    func testBothClipsPresent() {
        let availability = CompareClipAvailability.resolve(earlier: a, later: b)
        XCTAssertEqual(availability, .both(earlier: a, later: b))
        XCTAssertEqual(availability.url(.earlier), a)
        XCTAssertEqual(availability.url(.later), b)
        XCTAssertEqual(availability.clips.map(\.side), [.earlier, .later])
        XCTAssertEqual(availability.clips.map(\.url), [a, b])
        XCTAssertTrue(availability.hasAnyClip)
        XCTAssertNil(availability.shortfallLabel, "nothing is missing — say nothing")
        XCTAssertNil(availability.shortfallDetail)
    }

    /// Legacy sessions carry no `videoFileName`, and the retention sweep can
    /// take a take away. One clip is a normal state, and the pane that has
    /// one still plays.
    func testOnlyOneClipPresentNamesTheSideThatIsMissing() {
        let earlierOnly = CompareClipAvailability.resolve(earlier: a, later: nil)
        XCTAssertEqual(earlierOnly, .only(.earlier, a))
        XCTAssertEqual(earlierOnly.url(.earlier), a)
        XCTAssertNil(earlierOnly.url(.later))
        XCTAssertEqual(earlierOnly.clips.map(\.side), [.earlier],
                       "a missing take must not cost a decoder")
        XCTAssertTrue(earlierOnly.hasAnyClip)
        XCTAssertEqual(earlierOnly.shortfallLabel, "LATER CLIP MISSING")
        XCTAssertEqual(earlierOnly.shortfallDetail?.contains("later session"), true)

        let laterOnly = CompareClipAvailability.resolve(earlier: nil, later: b)
        XCTAssertEqual(laterOnly, .only(.later, b))
        XCTAssertNil(laterOnly.url(.earlier))
        XCTAssertEqual(laterOnly.url(.later), b)
        XCTAssertEqual(laterOnly.clips.map(\.side), [.later])
        XCTAssertEqual(laterOnly.shortfallLabel, "EARLIER CLIP MISSING")
        XCTAssertEqual(laterOnly.shortfallDetail?.contains("earlier session"), true)
    }

    /// Two legacy sessions compared: no band, no player, and an explanation
    /// instead of an empty rectangle.
    func testNeitherClipPresent() {
        let availability = CompareClipAvailability.resolve(earlier: nil, later: nil)
        XCTAssertEqual(availability, .neither)
        XCTAssertFalse(availability.hasAnyClip)
        XCTAssertTrue(availability.clips.isEmpty, "no clips means no players at all")
        XCTAssertNil(availability.url(.earlier))
        XCTAssertNil(availability.url(.later))
        XCTAssertEqual(availability.shortfallLabel, "NO CLIPS STORED")
        XCTAssertEqual(availability.shortfallDetail?.isEmpty, false)
    }

    /// Whatever is missing, the numbers are still the screen's floor — every
    /// state must say so rather than leaving a swimmer at a dead end.
    func testEveryShortfallPointsAtTheNumbersThatStillWork() {
        for availability in [CompareClipAvailability.only(.earlier, a),
                             .only(.later, b),
                             .neither] {
            XCTAssertEqual(availability.shortfallDetail?.contains("numbers below"), true,
                           "\(availability) left the swimmer with nothing")
        }
    }

    // MARK: - Pane geometry

    private let landscape = CGSize(width: 1920, height: 1080)
    private let portrait = CGSize(width: 1080, height: 1920)
    private let square = CGSize(width: 1080, height: 1080)

    func testTwoLandscapeTakesKeepTheLandscapeShape() {
        XCTAssertEqual(CompareVideoLayout.paneAspect([landscape, landscape]),
                       16.0 / 9.0, accuracy: 0.0001)
    }

    /// A true 9:16 pane in half a phone's width is a tower that pushes the
    /// transport off screen — portrait takes letterbox into 3:4 instead.
    func testPortraitTakesAreCappedRatherThanTowering() {
        XCTAssertEqual(CompareVideoLayout.paneAspect([portrait, portrait]),
                       3.0 / 4.0, accuracy: 0.0001)
    }

    /// Mixed orientations share one pane so the row keeps a straight edge:
    /// the taller clip sets the shape and the wider one gets the bars.
    func testMixedOrientationsTakeTheMorePortraitShape() {
        XCTAssertEqual(CompareVideoLayout.paneAspect([landscape, portrait]),
                       3.0 / 4.0, accuracy: 0.0001)
        XCTAssertEqual(CompareVideoLayout.paneAspect([square, landscape]),
                       1.0, accuracy: 0.0001)
    }

    /// Sizes arrive asynchronously and one side may have no clip at all — the
    /// band must have a shape to draw before either lands.
    func testUnknownSizesFallBackToTheFramingTheCameraCoaches() {
        XCTAssertEqual(CompareVideoLayout.paneAspect([nil, nil]),
                       CompareVideoLayout.defaultAspect, accuracy: 0.0001)
        XCTAssertEqual(CompareVideoLayout.paneAspect([nil, portrait]),
                       3.0 / 4.0, accuracy: 0.0001)
        XCTAssertEqual(CompareVideoLayout.paneAspect([.zero, landscape]),
                       16.0 / 9.0, accuracy: 0.0001)
    }

    func testPaneAspectStaysInsideItsBounds() {
        let extremes = [CGSize(width: 4000, height: 100), CGSize(width: 100, height: 4000)]
        for size in extremes {
            let aspect = CompareVideoLayout.paneAspect([size, nil])
            XCTAssertGreaterThanOrEqual(aspect, CompareVideoLayout.minAspect)
            XCTAssertLessThanOrEqual(aspect, CompareVideoLayout.maxAspect)
        }
    }

    // MARK: - Side

    func testSidesAreEachOthersOpposite() {
        XCTAssertEqual(ClipSide.earlier.other, .later)
        XCTAssertEqual(ClipSide.later.other, .earlier)
        XCTAssertEqual(ClipSide.earlier.label, "EARLIER")
        XCTAssertEqual(ClipSide.later.label, "LATER")
    }
}
