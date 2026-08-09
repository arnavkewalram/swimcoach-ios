import SwiftUI
import AVFoundation

/// Two clips held on one playhead — the driver behind Compare's side-by-side
/// band.
///
/// `ClipSyncMap` decides *what* synced means (one shared lap position, the
/// longer clip as the 1.0× reference); this owns the players that make it
/// true, and the lifetime of the two decoders that make it the heaviest thing
/// the app runs.
///
/// Lifetime rules, all of them load-bearing:
///   • Players are built once per appearance, in `load`, and only for sides
///     whose clip actually opened — a missing take costs nothing, and neither
///     does a stored one that will not play.
///   • Player and duration are adopted together or not at all:
///     `players[side] != nil` and `map.duration(side) > 0` are one fact, so
///     the pane, its label, its time code, its spoken label and the shortfall
///     copy cannot end up describing different screens.
///   • The periodic observer is attached to the reference player and removed
///     from *that same instance* in `teardown`; `AVPlayer` retains the block,
///     so a token removed from the wrong player leaks both the block and the
///     player it holds.
///   • `teardown` runs from `onDisappear`: it pauses, detaches both observers,
///     and drops each item with `replaceCurrentItem(with: nil)` before
///     releasing the players, so the decode pipelines go away with the screen
///     rather than whenever the last reference happens to drain.
///   • Backgrounding pauses. Two video pipelines held at rate in the
///     background is exactly the case iOS kills apps for.
@MainActor
@Observable
final class SyncedClipPair {

    /// Players for the sides that have a clip — one key, or two, or none.
    private(set) var players: [ClipSide: AVPlayer] = [:]
    /// Display-space clip sizes, for the shared pane aspect.
    private(set) var displaySizes: [ClipSide: CGSize] = [:]
    private(set) var map = ClipSyncMap(earlierDuration: nil, laterDuration: nil)
    /// The one shared playhead, 0…1 of the lap.
    private(set) var position: Double = 0
    private(set) var isPlaying = false
    private(set) var isLoaded = false
    /// True once `load` has decided which sides play. Until then the store's
    /// promise stands: degrading a pane before its asset has opened would
    /// flash "no clip" over footage that is one hop of `await` away.
    private(set) var hasResolvedClips = false

    /// While a finger is on the track the observer must not fight it.
    private(set) var isScrubbing = false
    /// The observer and the exact player it was added to.
    private var observation: (player: AVPlayer, token: Any)?
    private var endObserver: NSObjectProtocol?
    /// Bumped by every teardown, so a `load` still awaiting its assets when
    /// the screen goes knows not to adopt what it built.
    private var generation = 0

    /// How far the follower may drift before it is nudged back. Below this,
    /// correcting costs more than it fixes — a seek every tick would stutter
    /// the picture to fix an error nobody can see at 30 fps.
    private static let driftTolerance: Double = 0.12
    /// Seek accuracy when correcting drift: a frame, not a keyframe.
    private static let driftSeekTolerance = CMTime(value: 1, timescale: 30)

    // MARK: - Loading

    func load(_ availability: CompareClipAvailability) async {
        guard !isLoaded else { return }
        isLoaded = true
        let generation = self.generation

        var built: [ClipSide: AVPlayer] = [:]
        var durations: [ClipSide: Double] = [:]
        var sizes: [ClipSide: CGSize] = [:]

        for (side, url) in availability.clips {
            let asset = AVURLAsset(url: url)
            // A file that resolves is not a file that plays. `persist` copies
            // non-atomically and `url(forFileName:)` checks only existence, so
            // a take truncated by a kill mid-copy hands back a URL whose
            // duration will not load. Without a duration this side has no
            // timeline — no rate, no time code, no clock for the transport to
            // follow — so it is not a clip, and a player built for it would be
            // a live decoder behind a pane reading "—".
            guard let seconds = try? await asset.load(.duration).seconds,
                  ClipSyncMap.isPlayable(seconds) else { continue }
            durations[side] = seconds

            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let natural = try? await track.load(.naturalSize),
               let transform = try? await track.load(.preferredTransform) {
                sizes[side] = VideoTransform.displaySize(natural: natural, transform: transform)
            }
            let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            // Muted: two soundtracks at two rates is noise, and Review has
            // always previewed silently.
            player.isMuted = true
            // Hold the last frame at the end; the loop below decides when to
            // start over, so the pair restarts together or not at all.
            player.actionAtItemEnd = .pause
            built[side] = player
        }

        // Loading a clip's duration and track is a few hops of `await`, and a
        // swimmer can be off this screen inside that window. Adopting the pair
        // now would attach an observer and start playing two decoders that
        // nothing is left to stop — `onDisappear` has already fired.
        guard generation == self.generation else { return }

        players = built
        displaySizes = sizes
        map = ClipSyncMap(earlierDuration: durations[.earlier],
                          laterDuration: durations[.later])
        hasResolvedClips = true
        guard !players.isEmpty else { return }

        observeReference()
        seek(toPosition: position, precise: true)
        play()
    }

    // MARK: - Transport

    func togglePlayback() {
        Haptics.tap()
        if isPlaying { pause() } else { play() }
    }

    func play() {
        guard !players.isEmpty else { return }
        // At the end, play means play again — otherwise the mark flips to
        // pause over two frozen frames.
        if position >= 0.999 { seek(toPosition: 0, precise: true) }
        isPlaying = true
        applyRates()
    }

    func pause() {
        isPlaying = false
        for player in players.values { player.rate = 0 }
    }

    /// Rate is the whole sync mechanism: the reference runs at 1.0× and the
    /// shorter clip runs slow by exactly its length ratio, so both reach their
    /// own last frame at the same moment without a seek per tick.
    private func applyRates() {
        for (side, player) in players {
            player.playImmediately(atRate: map.rate(for: side))
        }
    }

    /// Move the shared playhead. `precise` seeks frame-exactly — right for a
    /// released finger or a frame nudge, wasteful for every event of a drag.
    func seek(toPosition p: Double, precise: Bool) {
        guard !players.isEmpty else { return }
        position = min(1, max(0, p.isFinite ? p : 0))
        let tolerance = precise ? CMTime.zero : Self.driftSeekTolerance
        for (side, player) in players {
            let time = CMTime(seconds: map.time(atPosition: position, in: side),
                              preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
        }
    }

    func endScrubbing(at p: Double) {
        seek(toPosition: p, precise: true)
        isScrubbing = false
        if isPlaying { applyRates() }
    }

    func scrub(to p: Double) {
        isScrubbing = true
        seek(toPosition: p, precise: false)
    }

    /// Nudge both clips by one source frame of the reference. Stepping is a
    /// paused act — comparing a catch position frame by frame is the reason
    /// it exists.
    func step(frames: Int) {
        guard !players.isEmpty else { return }
        Haptics.tap()
        pause()
        seek(toPosition: map.position(position, steppedBy: frames), precise: true)
    }

    // MARK: - Observation

    private func observeReference() {
        guard observation == nil, let reference = players[map.referenceSide] else { return }
        let token = reference.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 20), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
        observation = (reference, token)

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: reference.currentItem, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restart() }
        }
    }

    private func tick(_ time: CMTime) {
        guard !isScrubbing else { return }
        position = map.position(ofTime: CMTimeGetSeconds(time), in: map.referenceSide)
        correctDrift()
    }

    /// Rate-locked playback drifts a little — decoders start at slightly
    /// different moments and a slowed clip accumulates rounding. Nudge the
    /// follower back only once the gap is visible.
    private func correctDrift() {
        guard isPlaying else { return }
        let follower = map.referenceSide.other
        guard let player = players[follower], map.duration(follower) > 0 else { return }
        let expected = map.time(atPosition: position, in: follower)
        let actual = CMTimeGetSeconds(player.currentTime())
        guard actual.isFinite, abs(actual - expected) > Self.driftTolerance else { return }
        player.seek(to: CMTime(seconds: expected, preferredTimescale: 600),
                    toleranceBefore: Self.driftSeekTolerance,
                    toleranceAfter: Self.driftSeekTolerance)
    }

    /// Both clips end together by construction, so the reference reaching its
    /// last frame is the pair's cue to run the lap again.
    private func restart() {
        seek(toPosition: 0, precise: true)
        if isPlaying { applyRates() }
    }

    // MARK: - Teardown

    func teardown() {
        generation &+= 1
        pause()
        if let observation {
            observation.player.removeTimeObserver(observation.token)
            self.observation = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        for player in players.values {
            player.replaceCurrentItem(with: nil)
        }
        players = [:]
        // The map goes with the players it described. Leaving durations behind
        // would leave the pair claiming clips it no longer holds — the exact
        // split between "there is a clip" and "there is a player" this class
        // exists to keep closed.
        map = ClipSyncMap(earlierDuration: nil, laterDuration: nil)
        hasResolvedClips = false
        // A teardown mid-drag would otherwise leave the flag raised for the
        // next appearance, where it silently pins the playhead: `tick` returns
        // early forever and the transport never moves. Nothing reaches that
        // today — Compare is pushed, and a pushed pair is never loaded twice —
        // but the trap costs one line to remove and a screen redesign to find.
        isScrubbing = false
        isLoaded = false
    }
}
