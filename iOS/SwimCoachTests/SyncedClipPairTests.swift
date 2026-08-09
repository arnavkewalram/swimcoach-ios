import XCTest
import AVFoundation
@testable import SwimCoach

/// The driver behind Compare's side-by-side band, exercised against real
/// files: what it builds players for, what it refuses to, and what it leaves
/// behind when the screen goes.
///
/// `ClipSyncMap` is pinned as pure arithmetic in `CompareClipsTests`; this is
/// the part that owns two decoders, so the cases that matter are the ones
/// where a clip is not what the store said it was.
///
/// Not covered here, deliberately — see the notes on each test: anything that
/// needs a rendered frame, and the internals of `AVPlayer`'s own observer
/// bookkeeping, which the framework does not expose.
@MainActor
final class SyncedClipPairTests: XCTestCase {

    // MARK: - Fixtures

    /// The bundled cartoon: a real, openable clip. Skipped rather than failed
    /// when the resource is absent, matching `OverlayVideoExporterTests`.
    private func playableClip() throws -> URL {
        guard let url = Bundle.main.url(forResource: "swim_test", withExtension: "mp4") else {
            throw XCTSkip("demo video not bundled")
        }
        return url
    }

    /// A file that exists, resolves to a URL, and will not open — what
    /// `SessionVideoStore.persist` leaves behind when a non-atomic `copyItem`
    /// is killed part way. Zero bytes is the kill at the start of the copy;
    /// a garbage prefix is the kill part way through.
    private func unopenableClip(bytes: Int) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncedClipPairTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("truncated.mp4")
        try Data(repeating: 0x21, count: bytes).write(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "premise: the broken take is a file that exists")
        return url
    }

    /// Every side that reports a length the map will drive a clip with.
    private func sidesWithDuration(_ pair: SyncedClipPair) -> Set<ClipSide> {
        Set(ClipSide.allCases.filter { pair.map.duration($0) > 0 })
    }

    // MARK: - What becomes a player

    /// The bug this file was written for. A stored file that will not open has
    /// no duration, so it has no timeline, no rate and no time code — and a
    /// player built for it anyway put a live `AVPlayerLayer` behind a pane
    /// whose code read "—" while VoiceOver said there was no clip.
    func testASideWhoseClipWillNotOpenNeverBecomesAPlayer() async throws {
        let good = try playableClip()
        let broken = try unopenableClip(bytes: 4_096)
        let pair = SyncedClipPair()
        defer { pair.teardown() }

        await pair.load(.both(earlier: good, later: broken))

        XCTAssertNotNil(pair.players[.earlier], "the readable side still plays")
        XCTAssertNil(pair.players[.later], "an unreadable file is not a clip")
        XCTAssertGreaterThan(pair.map.duration(.earlier), 0)
        XCTAssertEqual(pair.map.duration(.later), 0)
    }

    /// Zero bytes is the same answer as garbage: the copy died earlier, that
    /// is all.
    func testAnEmptyFileIsNotAClipEither() async throws {
        let pair = SyncedClipPair()
        defer { pair.teardown() }

        await pair.load(.only(.later, try unopenableClip(bytes: 0)))

        XCTAssertTrue(pair.players.isEmpty)
        XCTAssertTrue(pair.map.isEmpty)
    }

    /// One fact, not two. Everything the band draws — the label tint, the
    /// pane, its time code, its spoken label — reads one of these two and they
    /// must never disagree.
    func testAPlayerAndAUsableDurationAreTheSameFact() async throws {
        let good = try playableClip()
        let broken = try unopenableClip(bytes: 4_096)

        for availability: CompareClipAvailability in [
            .both(earlier: good, later: good),
            .both(earlier: good, later: broken),
            .both(earlier: broken, later: good),
            .both(earlier: broken, later: broken),
            .only(.earlier, good),
            .only(.later, broken),
            .neither,
        ] {
            let pair = SyncedClipPair()
            await pair.load(availability)
            XCTAssertEqual(Set(pair.players.keys), sidesWithDuration(pair),
                           "\(availability) split players from durations")
            pair.teardown()
        }
    }

    /// The transport follows the reference side's clock, and the periodic
    /// observer is attached to the reference player — so a pair that holds any
    /// player at all must hold that one.
    ///
    /// Before the fix this was reachable: a single unreadable clip left both
    /// durations at zero, `referenceSide` broke the tie toward `.later`, and
    /// the observer had nothing to attach to while the other side played on. A
    /// frozen playhead, `0:00 / 0:00`, dead frame steps and no loop.
    func testWhateverPlaysIncludesTheSideTheObserverNeeds() async throws {
        let good = try playableClip()
        let broken = try unopenableClip(bytes: 4_096)

        let cases: [(availability: CompareClipAvailability, plays: Bool)] = [
            (.both(earlier: good, later: good), true),
            (.both(earlier: good, later: broken), true),
            (.both(earlier: broken, later: good), true),
            (.only(.earlier, good), true),
            (.only(.later, good), true),
            // The dead-transport case exactly: one clip, and it will not open.
            // Both durations stay at zero, `referenceSide` breaks the tie
            // toward `.later`, and a player on `.earlier` would be a decoder
            // running under an observer that was never attached.
            (.only(.earlier, broken), false),
            (.both(earlier: broken, later: broken), false),
        ]
        for (availability, plays) in cases {
            let pair = SyncedClipPair()
            await pair.load(availability)
            XCTAssertEqual(!pair.players.isEmpty, plays,
                           "\(availability) played the wrong number of clips")
            if !pair.players.isEmpty {
                XCTAssertNotNil(pair.players[pair.map.referenceSide],
                                "\(availability) left the transport without a clock")
            }
            pair.teardown()
        }
    }

    /// A pair with nothing to play stays inert: no player, no rate, and a
    /// transport that reports the empty state rather than running against a
    /// clip that is not there.
    func testAPairWithNothingPlayableNeverStarts() async throws {
        let pair = SyncedClipPair()
        defer { pair.teardown() }

        await pair.load(.only(.earlier, try unopenableClip(bytes: 4_096)))

        XCTAssertTrue(pair.players.isEmpty)
        XCTAssertFalse(pair.isPlaying, "nothing to play must not report playing")
        XCTAssertTrue(pair.map.isEmpty)
        XCTAssertEqual(pair.map.referenceDuration, 0)
    }

    // MARK: - What the band is told

    /// The shortfall card is the only thing that explains an empty pane, and
    /// it must speak about what actually opened: a truncated take otherwise
    /// leaves `.both` on screen — no explanation at all — beside a pane that
    /// says NO CLIP.
    func testABrokenTakeIsExplainedByTheShortfallCard() async throws {
        let good = try playableClip()
        let broken = try unopenableClip(bytes: 4_096)
        let stored = CompareClipAvailability.both(earlier: good, later: broken)
        let pair = SyncedClipPair()
        defer { pair.teardown() }

        XCTAssertFalse(pair.hasResolvedClips, "nothing is known before the assets open")

        await pair.load(stored)

        XCTAssertTrue(pair.hasResolvedClips)
        let shown = stored.limited(toPlayable: Set(pair.players.keys))
        XCTAssertEqual(shown, .only(.earlier, good))
        XCTAssertEqual(shown.shortfallLabel, "LATER CLIP MISSING")
    }

    /// Two clips that both open leave the band saying nothing, which is the
    /// control for the test above.
    func testTwoGoodClipsExplainNothing() async throws {
        let good = try playableClip()
        let stored = CompareClipAvailability.both(earlier: good, later: good)
        let pair = SyncedClipPair()
        defer { pair.teardown() }

        await pair.load(stored)

        XCTAssertEqual(stored.limited(toPlayable: Set(pair.players.keys)), stored)
        XCTAssertEqual(pair.players.count, 2)
    }

    // MARK: - Lifetime

    /// Loading a clip is a few hops of `await` and a swimmer can be off this
    /// screen inside that window. A load that lands after `onDisappear` must
    /// not adopt what it built: `teardown` has already run, so nothing is left
    /// to attach an observer to it, pause it, or release it.
    func testALoadThatLandsAfterTeardownAdoptsNothing() async throws {
        let good = try playableClip()
        let pair = SyncedClipPair()

        let load = Task { await pair.load(.both(earlier: good, later: good)) }
        // Hand the loop to `load` until it is past its generation capture and
        // suspended on the asset — tearing down before it starts would test
        // the re-entrancy guard instead.
        while !pair.isLoaded { await Task.yield() }
        pair.teardown()
        await load.value

        XCTAssertTrue(pair.players.isEmpty, "a late load must not adopt two decoders")
        XCTAssertFalse(pair.isPlaying, "…and must not start them")
        XCTAssertTrue(pair.map.isEmpty)
        XCTAssertFalse(pair.hasResolvedClips)
        XCTAssertFalse(pair.isLoaded, "the pair is free to load again on the next appearance")
    }

    /// The same `load` with no teardown in the middle — without this the test
    /// above would pass on a pair that never loads anything.
    func testTheSameLoadUninterruptedDoesAdoptItsPlayers() async throws {
        let good = try playableClip()
        let pair = SyncedClipPair()
        defer { pair.teardown() }

        let load = Task { await pair.load(.both(earlier: good, later: good)) }
        while !pair.isLoaded { await Task.yield() }
        await load.value

        XCTAssertEqual(pair.players.count, 2)
        XCTAssertTrue(pair.isPlaying)
    }

    /// `teardown` runs from `onDisappear`, which SwiftUI is free to deliver
    /// more than once. The second pass must not remove an observer token that
    /// is already gone — `AVPlayer` traps on that — so the record has to be
    /// cleared with the removal, not merely read.
    func testTearingDownTwiceIsSafe() async throws {
        let good = try playableClip()
        let pair = SyncedClipPair()

        await pair.load(.both(earlier: good, later: good))
        XCTAssertEqual(pair.players.count, 2, "premise: there was an observer to remove")

        pair.teardown()
        pair.teardown()

        XCTAssertTrue(pair.players.isEmpty)
        XCTAssertFalse(pair.isPlaying)
    }

    /// A torn-down pair holds nothing, so every control is a no-op rather than
    /// a call into released players.
    func testATornDownPairIgnoresItsTransport() async throws {
        let good = try playableClip()
        let pair = SyncedClipPair()

        await pair.load(.only(.later, good))
        pair.teardown()

        pair.play()
        XCTAssertFalse(pair.isPlaying)
        pair.togglePlayback()
        XCTAssertFalse(pair.isPlaying)
        pair.step(frames: 1)
        pair.seek(toPosition: 0.5, precise: true)
        XCTAssertEqual(pair.position, 0, "a pair with no clips has nowhere to seek to")
    }

    /// The screen can leave with a finger still on the track. The flag that
    /// tells the observer to stand off is cleared by the end of a drag — and,
    /// since a drag can end by the screen going away, by `teardown` too.
    /// Left raised, it pins the playhead on the next appearance: `tick`
    /// returns early forever and the transport never moves again.
    func testAFingerOnTheTrackDoesNotSurviveTheScreen() async throws {
        let good = try playableClip()
        let pair = SyncedClipPair()
        defer { pair.teardown() }

        await pair.load(.only(.later, good))

        pair.scrub(to: 0.4)
        XCTAssertTrue(pair.isScrubbing, "premise: a drag stands the observer off")
        pair.endScrubbing(at: 0.4)
        XCTAssertFalse(pair.isScrubbing)

        pair.scrub(to: 0.6)
        pair.teardown()
        XCTAssertFalse(pair.isScrubbing, "a drag cannot outlive the players it was driving")

        // …and the pair is genuinely reusable afterwards.
        await pair.load(.only(.later, good))
        XCTAssertEqual(pair.players.count, 1)
        XCTAssertFalse(pair.isScrubbing)
    }

    // MARK: - Not tested here, and why
    //
    // • "The periodic observer is removed from the *same* `AVPlayer` it was
    //   added to." `AVPlayer` publishes no observer list and treats a token
    //   removed from the wrong instance as undefined rather than trapping, so
    //   no assertion can tell a correct removal from a wrong one. What CI can
    //   hold is the half that is observable: the record is cleared with the
    //   removal, so a repeated teardown cannot remove the same token twice
    //   (`testTearingDownTwiceIsSafe`).
    //
    // • Teardown *ordering* — pause, detach, `replaceCurrentItem(nil)`, then
    //   release — is about when the decode pipelines go away. That is visible
    //   in a memory graph or an Instruments trace, not in any value the class
    //   exposes; a test asserting it would be asserting the implementation it
    //   just read.
    //
    // • Backgrounding pausing the pair lives in `CompareVideoBand`'s
    //   `scenePhase` handler, and neither a unit test nor a UI test can read
    //   an `AVPlayer`'s rate across the process boundary. `pause()` itself is
    //   covered above.
}
