import CoreGraphics
import Foundation

/// Which of the two compared swims a value belongs to.
enum ClipSide: String, Hashable, CaseIterable {
    case earlier, later

    var label: String { rawValue.uppercased() }
    var other: ClipSide { self == .earlier ? .later : .earlier }
}

// MARK: - Sync

/// What "synced" means when two swims are played under one transport.
///
/// The two clips are almost never the same length — the same lap filmed a
/// fortnight apart differs by whole seconds, and the recordings are trimmed by
/// hand. So the transport does not drive wall-clock seconds. It drives one
/// shared **lap position**, 0…1, and each clip seeks to that fraction of its
/// own duration.
///
/// Why proportional and not absolute time:
///   • Each clip is one lap, filmed side-on, start to finish. Strokes are
///     spread evenly along a lap, so the same *fraction* of the lap is the
///     same *stroke phase* — the catch at 40% of the lap lines up with the
///     catch at 40% of the lap, which is exactly the comparison a swimmer is
///     making. Absolute seconds line up nothing: two seconds into a 12-second
///     lap and two seconds into an 18-second lap are different strokes.
///   • Absolute time also has to answer "what does the shorter clip show once
///     it runs out?", and every answer is bad — a frozen last frame beside a
///     live swimmer reads as a stalled player, and the comparison silently
///     stops being a comparison.
///
/// The assumption it rests on — even tempo across the clip, both clips
/// covering the same swim — is stated on screen rather than hidden, and the
/// per-pane time codes show the two real clip lengths so nothing is disguised.
///
/// Playback keeps that mapping true by rate, not by seeking every frame: the
/// **longer clip is the reference and plays at 1.0×**, and the shorter plays
/// at `shorter / longer`, so both cross their own finish at the same moment.
/// Slowing the shorter clip rather than speeding the longer one means nothing
/// is ever played faster than it was swum — the slowed side is the one you
/// gain detail on, and no rate above 1.0 is ever asked of the decoder.
struct ClipSyncMap: Equatable {
    /// Sanitised clip lengths in seconds. Zero means "no usable clip on that
    /// side" — an unloaded asset reports `.nan`, and a nil duration and a
    /// missing file have to behave identically here.
    let earlierDuration: Double
    let laterDuration: Double

    /// Frame step for the transport's nudge controls. Capture is 30 fps
    /// (see the model contract), and a step finer than the source frame is
    /// a seek to the same frame.
    static let stepFPS: Double = 30

    init(earlierDuration: Double?, laterDuration: Double?) {
        self.earlierDuration = Self.sanitised(earlierDuration)
        self.laterDuration = Self.sanitised(laterDuration)
    }

    private static func sanitised(_ d: Double?) -> Double {
        guard let d, d.isFinite, d > 0 else { return 0 }
        return d
    }

    /// The one test for "is there a clip on this side", exposed because the
    /// driver has to apply the *same* one before it builds a player.
    ///
    /// A length this rejects becomes a zero duration, which the map defines as
    /// "no usable clip on that side" — so a player built behind it would be a
    /// live decoder under a pane every other part of the screen calls empty,
    /// with no clock for the transport to follow.
    static func isPlayable(_ duration: Double?) -> Bool {
        sanitised(duration) > 0
    }

    func duration(_ side: ClipSide) -> Double {
        side == .earlier ? earlierDuration : laterDuration
    }

    /// Is there anything to play at all?
    var isEmpty: Bool { earlierDuration == 0 && laterDuration == 0 }

    /// The side whose clock the transport follows: the longer clip, which
    /// plays untouched at 1.0×. With one clip it is trivially that clip.
    var referenceSide: ClipSide {
        laterDuration >= earlierDuration ? .later : .earlier
    }

    /// Wall-clock length of one synced run — the longer clip's own length.
    var referenceDuration: Double { max(earlierDuration, laterDuration) }

    /// Where in `side`'s own timeline a shared lap position falls.
    func time(atPosition position: Double, in side: ClipSide) -> Double {
        clamped(position) * duration(side)
    }

    /// The shared lap position a time in `side`'s own timeline represents.
    func position(ofTime time: Double, in side: ClipSide) -> Double {
        let d = duration(side)
        guard d > 0, time.isFinite else { return 0 }
        return clamped(time / d)
    }

    /// Playback rate that keeps `side` on the shared position: 1.0 for the
    /// reference (and for anything with nothing to play), below 1.0 for the
    /// shorter clip.
    func rate(for side: ClipSide) -> Float {
        let d = duration(side)
        let reference = referenceDuration
        guard d > 0, reference > 0 else { return 1 }
        return Float(d / reference)
    }

    /// One source frame expressed as a shared-position delta, so a nudge
    /// moves the reference clip by exactly one frame and the follower by the
    /// matching fraction.
    func positionStep(frames: Int) -> Double {
        let reference = referenceDuration
        guard reference > 0 else { return 0 }
        return Double(frames) / Self.stepFPS / reference
    }

    /// Position advanced by `frames`, clamped to the clip.
    func position(_ position: Double, steppedBy frames: Int) -> Double {
        clamped(position + positionStep(frames: frames))
    }

    private func clamped(_ p: Double) -> Double {
        guard p.isFinite else { return 0 }
        return min(1, max(0, p))
    }
}

// MARK: - Availability

/// Which of the two compared sessions still has a clip to play.
///
/// Either side can come up empty and both are ordinary, not error states:
/// sessions analyzed before clips were stored carry no `videoFileName` at
/// all, photo-library imports may never have been copied in, and the store's
/// retention sweep prunes takes nobody claimed. Compare therefore never
/// assumes two clips — the numbers are the screen's floor, and video is what
/// it adds when the footage is there.
enum CompareClipAvailability: Equatable {
    case both(earlier: URL, later: URL)
    case only(ClipSide, URL)
    case neither

    static func resolve(earlier: URL?, later: URL?) -> CompareClipAvailability {
        switch (earlier, later) {
        case let (e?, l?):  return .both(earlier: e, later: l)
        case let (e?, nil): return .only(.earlier, e)
        case let (nil, l?): return .only(.later, l)
        case (nil, nil):    return .neither
        }
    }

    /// The clip for one side, if it has one.
    func url(_ side: ClipSide) -> URL? {
        switch self {
        case let .both(e, l):          return side == .earlier ? e : l
        case let .only(present, url):  return side == present ? url : nil
        case .neither:                 return nil
        }
    }

    /// The sides that actually have something to play, in screen order —
    /// what the driver builds players from, so a missing take never costs a
    /// decoder.
    var clips: [(side: ClipSide, url: URL)] {
        ClipSide.allCases.compactMap { side in url(side).map { (side, $0) } }
    }

    /// Is there a band to draw at all?
    var hasAnyClip: Bool { self != .neither }

    /// The same answer, narrowed to the sides whose clip actually opened.
    ///
    /// Existing is not the same as playing. `SessionVideoStore.persist` copies
    /// non-atomically and `url(forFileName:)` asks only whether a file is
    /// there, so a take truncated by a kill mid-copy still resolves to a URL
    /// and still has no readable duration. A side like that has nothing to
    /// show, and "both clips are here" printed over an empty pane explains
    /// nothing — so it folds into the same shortfall a missing take gets.
    func limited(toPlayable playable: Set<ClipSide>) -> CompareClipAvailability {
        .resolve(earlier: playable.contains(.earlier) ? url(.earlier) : nil,
                 later: playable.contains(.later) ? url(.later) : nil)
    }

    /// Headline for the state, uppercased for the micro-label slot. Nil when
    /// both clips are present and there is nothing to explain.
    var shortfallLabel: String? {
        switch self {
        case .both:               return nil
        case let .only(side, _):  return "\(side.other.label) CLIP MISSING"
        case .neither:            return "NO CLIPS TO PLAY"
        }
    }

    /// What is missing and why, in plain words. Nil when both clips exist.
    ///
    /// The reason is a list of causes the swimmer cannot tell apart from here,
    /// so it has to cover all of them. Since About gained "delete clips older
    /// than…", there are three: never kept, dropped on purpose, or unreadable.
    /// Hence **footage**, not "take" — a take is specifically an unclaimed clip
    /// waiting on the Takes screen, and the clip behind a compared session is
    /// by definition not one — and **deleted**, the verb that control uses, so
    /// a swimmer who freed the space recognises their own doing instead of
    /// being offered damage as the likelier explanation.
    var shortfallDetail: String? {
        switch self {
        case .both:
            return nil
        case let .only(side, _):
            return "The \(side.other.rawValue) session has no clip to play — it was "
                 + "analyzed before clips were kept, or its footage has since been "
                 + "deleted or damaged. The \(side.rawValue) swim plays on its own; "
                 + "the numbers below compare both."
        case .neither:
            return "Neither session has a clip that plays, so there is nothing to "
                 + "show side by side. The numbers below still compare both swims."
        }
    }
}

// MARK: - Layout

/// Geometry for the side-by-side band.
///
/// The panes are always side by side, never stacked: two swims stacked on a
/// phone put one of them off screen at the moment the whole point is seeing
/// them at once, and the app is portrait-only (see `project.yml`), so the
/// width the band gets is the width it will ever get.
///
/// Clip orientation is a different question — a take can be portrait or
/// landscape and the two sides need not match. Both panes share one aspect so
/// the row keeps a straight top and bottom edge; `resizeAspect` letterboxes
/// whatever does not fill it.
enum CompareVideoLayout {
    /// Nothing loaded yet: hold the shape of a landscape take, the framing
    /// the camera screen coaches for.
    static let defaultAspect: CGFloat = 16.0 / 9.0
    /// A pane never gets taller than 4:3 portrait. A true 9:16 pane in half
    /// the screen width is a 300pt tower that pushes the transport under the
    /// fold; a portrait clip letterboxes into this instead.
    static let minAspect: CGFloat = 3.0 / 4.0
    /// …and never wider than the landscape framing, so a wide clip does not
    /// squeeze the pair into a letterbox strip.
    static let maxAspect: CGFloat = 16.0 / 9.0

    /// One aspect for both panes: the more portrait of the loaded clips, so
    /// the taller take fills its pane and the wider one gets the bars.
    ///
    /// Sizes must already be in display space (`VideoTransform.displaySize`),
    /// otherwise a rotated portrait capture measures as landscape.
    static func paneAspect(_ sizes: [CGSize?]) -> CGFloat {
        let aspects = sizes.compactMap { size -> CGFloat? in
            guard let size, size.width > 0, size.height > 0 else { return nil }
            return size.width / size.height
        }
        guard let narrowest = aspects.min() else { return defaultAspect }
        return min(maxAspect, max(minAspect, narrowest))
    }
}
