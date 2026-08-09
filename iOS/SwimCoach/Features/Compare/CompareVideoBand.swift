import SwiftUI

/// Compare's side-by-side band: the two swims on one playhead.
///
/// Compare answered "am I improving?" in numbers only, which is the wrong
/// primary answer for a technique app — the useful comparison is watching the
/// two laps beside each other and seeing the catch that changed. The numbers
/// stay exactly as they were, below; this is what the screen leads with when
/// there is footage to lead with.
///
/// Either clip may be missing — or stored and unopenable, which is the same
/// thing to a screen that has to play it (see `CompareClipAvailability`) — and
/// the band degrades in one step: the pane that has no clip is drawn as an
/// empty field with a stated reason, never as a black rectangle that looks
/// like a player that failed to start.
struct CompareVideoBand: View {
    let earlier: AnalysisResult
    let later: AnalysisResult
    let availability: CompareClipAvailability

    @State private var pair = SyncedClipPair()
    @Environment(\.scenePhase) private var scenePhase

    /// Gutter between the two panes — narrow enough that the pair reads as
    /// one band, wide enough that the two swims never look like one shot.
    private static let paneGap: CGFloat = 10

    private var paneAspect: CGFloat {
        CompareVideoLayout.paneAspect(ClipSide.allCases.map { pair.displaySizes[$0] })
    }

    /// Does this side have a clip? One question, asked one way.
    ///
    /// `SyncedClipPair` builds a player only for a side whose duration loaded,
    /// so a player is exactly a playable clip — the label tint, the pane, its
    /// time code and its spoken label all read the same fact and cannot
    /// contradict each other.
    private func hasClip(_ side: ClipSide) -> Bool { pair.players[side] != nil }

    /// What the band can actually show, which is not always what the store
    /// promised: a stored file may exist and still not open (see
    /// `CompareClipAvailability.limited(toPlayable:)`). Until the pair has
    /// resolved its clips, the store's answer stands.
    private var shown: CompareClipAvailability {
        guard pair.hasResolvedClips else { return availability }
        return availability.limited(toPlayable: Set(pair.players.keys))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Side by side")

            if shown.hasAnyClip {
                if case .both = shown { syncNote }
                panes
                transport
                footnoteRow
            }

            shortfallCard
        }
        .task { await pair.load(availability) }
        // Two decoders is the heaviest thing this app runs — they go when the
        // screen goes, not whenever the players happen to be released.
        .onDisappear { pair.teardown() }
        // Leaving the app mid-playback must not leave two pipelines at rate.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { pair.pause() }
        }
    }

    // MARK: - Panes

    private var syncNote: some View {
        Text("Both clips run start to finish together, so the same point of "
             + "the lap lines up — not the same second.")
            .font(.caption)
            .foregroundStyle(DS.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Side by side, not stacked. Checked on device rather than assumed: a
    /// stacked pair draws each swim 2.3× larger, and it costs the comparison
    /// everything — at 393pt the second pane's foot lands past the fold, so
    /// the transport, the sync note and the frame nudges are all off screen
    /// at rest, and the two swimmers sit ~400pt apart with nothing to hold
    /// them together. Half-width panes are small, but both swims and the
    /// controls that drive them stay in one glance, which is the entire
    /// reason the screen exists.
    private var panes: some View {
        HStack(alignment: .top, spacing: Self.paneGap) {
            pane(.earlier)
            pane(.later)
        }
    }

    private func pane(_ side: ClipSide) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(side.label)
                .font(.sectionLabel)
                .tracking(1.4)
                .foregroundStyle(hasClip(side) ? DS.accent : DS.inkTertiary)

            Group {
                if let player = pair.players[side] {
                    ClipPlayerSurface(player: player)
                        .background(Color.black)
                } else {
                    emptyField
                }
            }
            .aspectRatio(paneAspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.border, lineWidth: 1))

            // Each pane's own clock. No date here: the score head-to-head
            // directly above already dates both columns in this same order,
            // and a second date under each pane says nothing new while the
            // clip lengths — the thing the sync is reconciling — do.
            Text(paneCode(side))
                .font(.custom(GroteskWeight.medium.postScriptName,
                              size: 10, relativeTo: .caption2))
                .monospacedDigit()
                .tracking(0.6)
                .foregroundStyle(DS.inkTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(paneSpoken(side))
    }

    /// What a pane with no clip shows. A ruled empty field in the sheet's own
    /// language — the meet sheet's blank lane, not a dead player.
    private var emptyField: some View {
        ZStack {
            DS.surface2
            VStack(spacing: 6) {
                Image(systemName: "video.slash")
                    .font(.footnote)
                    .accessibilityHidden(true)
                Text("NO CLIP")
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                    .tracking(1.2)
            }
            .foregroundStyle(DS.inkTertiary)
        }
    }

    // MARK: - Transport

    private var transport: some View {
        ClipTransportBar(
            position: pair.position,
            isPlaying: pair.isPlaying,
            timeCode: ClipTime.code(referenceTime, of: pair.map.referenceDuration),
            spokenPosition: "\(Int((pair.position * 100).rounded())) percent through both clips",
            // One second of the reference clip per VoiceOver increment.
            adjustStep: pair.map.referenceDuration > 0 ? 1 / pair.map.referenceDuration : 0.05,
            onToggle: { pair.togglePlayback() },
            onScrub: { pair.scrub(to: $0) },
            onScrubEnd: { pair.endScrubbing(at: $0) }
        )
    }

    /// The line under the transport: what the sync is doing, and the frame
    /// nudges that make a still comparison possible.
    private var footnoteRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(syncLabel)
                .font(.custom(GroteskWeight.medium.postScriptName,
                              size: 9, relativeTo: .caption2))
                .tracking(1.2)
                .foregroundStyle(DS.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            stepButton(frames: -1, symbol: "backward.frame.fill", label: "Step back one frame")
            stepButton(frames: 1, symbol: "forward.frame.fill", label: "Step forward one frame")
        }
    }

    /// Names the slowed side and by how much, rather than leaving a swimmer to
    /// wonder why one clip looks unhurried.
    private var syncLabel: String {
        let follower = pair.map.referenceSide.other
        let rate = pair.map.rate(for: follower)
        guard hasClip(follower), rate > 0, rate < 0.995 else {
            return "SYNCED · LAP POSITION"
        }
        return "SYNCED · \(follower.label) ×\(String(format: "%.2f", rate))"
    }

    private func stepButton(frames: Int, symbol: String, label: String) -> some View {
        Button {
            pair.step(frames: frames)
        } label: {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.accent)
                .frame(width: ClipTransportBar.hitTarget,
                       height: ClipTransportBar.hitTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    // MARK: - Shortfall

    @ViewBuilder
    private var shortfallCard: some View {
        if let label = shown.shortfallLabel,
           let detail = shown.shortfallDetail {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 9))
                    .tracking(1.2)
                    .foregroundStyle(DS.severityModerate)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(DS.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassCard()
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Values

    private func result(_ side: ClipSide) -> AnalysisResult {
        side == .earlier ? earlier : later
    }

    private var referenceTime: Double {
        pair.map.time(atPosition: pair.position, in: pair.map.referenceSide)
    }

    /// Each pane carries its own clip's time code, so two different clip
    /// lengths moving under one playhead is visible rather than implied.
    private func paneCode(_ side: ClipSide) -> String {
        guard hasClip(side) else { return "—" }
        return ClipTime.code(pair.map.time(atPosition: pair.position, in: side),
                             of: pair.map.duration(side))
    }

    private func paneSpoken(_ side: ClipSide) -> String {
        let date = result(side).analyzedAt.formatted(date: .abbreviated, time: .omitted)
        guard hasClip(side) else {
            return "\(side.label.capitalized) swim, \(date). No clip to play."
        }
        return "\(side.label.capitalized) swim, \(date), "
             + "\(ClipTime.code(pair.map.duration(side))) long."
    }
}
