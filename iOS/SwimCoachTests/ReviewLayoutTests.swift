import XCTest
import SwiftUI
@testable import SwimCoach

/// Review's layout rules, pinned.
///
/// The screen fits four blocks — masthead, clip band, transport, checklist —
/// above a fixed action bar. Three of those grow with Dynamic Type; the band
/// is the one that must shrink to pay for them. That trade was previously a
/// bare `.frame(height: 224)` with a comment admitting it only held "at the
/// default type size", and it regressed silently: at accessibility sizes the
/// checklist slid under the action bar with item 02 clipped mid-glyph.
final class ReviewLayoutTests: XCTestCase {

    private let allSizes: [DynamicTypeSize] = [
        .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
        .accessibility1, .accessibility2, .accessibility3,
        .accessibility4, .accessibility5,
    ]

    func testClipBandKeepsItsFullHeightAtDefaultTypeSize() {
        XCTAssertEqual(ReviewView.clipBandHeight(for: .large), 224)
    }

    func testClipBandNeverGrowsAsTypeGrows() {
        for (smaller, larger) in zip(allSizes, allSizes.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                ReviewView.clipBandHeight(for: smaller),
                ReviewView.clipBandHeight(for: larger),
                "band grew from \(smaller) to \(larger) — text must win, not the video")
        }
    }

    /// 110pt is what an 844pt phone (iPhone 14/15/16 class) needs the band to
    /// give back before all three rules clear the action bar; 124pt fit the
    /// 874pt Pro only.
    func testClipBandCollapsesAtAccessibilitySizes() {
        for size in allSizes where size.isAccessibilitySize {
            XCTAssertLessThanOrEqual(
                ReviewView.clipBandHeight(for: size), 110,
                "band did not yield enough room at \(size) for the checklist")
        }
    }

    /// A preview still has to read as a preview — collapsing to nothing would
    /// defeat the point of a keep-or-retake screen.
    func testClipBandStaysBigEnoughToJudgeFraming() {
        for size in allSizes {
            XCTAssertGreaterThanOrEqual(ReviewView.clipBandHeight(for: size), 100)
        }
    }

    /// Play/pause is the only playback control on the screen, and the track is
    /// the only seek affordance; both drawn marks are deliberately smaller
    /// than their targets.
    func testScrubberTargetsMeetTheHIGMinimum() {
        XCTAssertGreaterThanOrEqual(ClipScrubber.hitTarget, 44)
    }

    func testClipTimeFormatsAsAMeetSheetCode() {
        XCTAssertEqual(ClipTime.code(0), "0:00")
        XCTAssertEqual(ClipTime.code(7.4), "0:07")
        XCTAssertEqual(ClipTime.code(59.6), "1:00")
        XCTAssertEqual(ClipTime.code(125), "2:05")
    }

    /// Duration is `.nan` until the asset loads, and negative never happens —
    /// but neither may render as garbage next to a live time code.
    func testClipTimeSurvivesUnloadedDurations() {
        XCTAssertEqual(ClipTime.code(.nan), "0:00")
        XCTAssertEqual(ClipTime.code(.infinity), "0:00")
        XCTAssertEqual(ClipTime.code(-12), "0:00")
    }
}
