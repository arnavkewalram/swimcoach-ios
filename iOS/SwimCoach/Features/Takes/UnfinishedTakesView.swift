import SwiftUI
import SwiftData
import AVFoundation

/// Recovery for clips the app adopted but never scored.
///
/// Filming claims a file into `SessionVideoStore` the moment recording stops,
/// so a take survives a failed analysis, a cancelled run, or a user who backed
/// out — but until this screen existed nothing ever listed those files, and the
/// launch sweep deleted them. `UnfinishedTakes` now holds them for a retention
/// window and this is where they are offered back: poster frame, when it was
/// filmed, how long it runs, and the two answers worth having — Analyze or
/// Delete.
///
/// The list is derived from the filesystem rather than stored, so it is always
/// the truth: a take claimed by a session on this visit is simply absent when
/// the screen re-reads.
struct UnfinishedTakesView: View {
    @Environment(AppRouter.self) private var router
    @Query private var sessions: [SwimSession]

    @State private var takes: [UnfinishedTakes.Take] = []
    @State private var confirmingClearAll = false

    /// Days, for copy that must not drift from the policy it describes.
    private var retentionDays: Int {
        Int((UnfinishedTakes.retention / 86_400).rounded())
    }

    var body: some View {
        ZStack {
            DS.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        masthead

                        if takes.isEmpty {
                            allClear
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(takes) { take in
                                    TakeCard(take: take,
                                             onAnalyze: { analyze(take) },
                                             onDelete: { delete(take) })
                                }
                            }
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 24)
                }
                .scrollBounceBehavior(.basedOnSize)

                if !takes.isEmpty { clearAllBar }
            }
        }
        // Recomputed on every appearance, not just the first: analyzing a take
        // claims it, and Back lands here again.
        .task { refresh() }
        .onChange(of: router.path.count) { _, _ in refresh() }
        .navigationTitle("Takes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Takes")
                    .font(.grotesk(17, .medium))
                    .foregroundStyle(DS.ink)
            }
        }
        .toolbarBackground(DS.background, for: .navigationBar)
        .confirmationDialog("Delete every unfinished take?",
                            isPresented: $confirmingClearAll,
                            titleVisibility: .visible) {
            Button("Delete \(takes.count) take\(takes.count == 1 ? "" : "s")",
                   role: .destructive) { clearAll() }
            Button("Keep them", role: .cancel) {}
        } message: {
            Text("The clips are removed from this device. Analyzed sessions are not affected.")
        }
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("UNFINISHED")
                    .font(.sectionLabel)
                    .tracking(2.0)
                    .foregroundStyle(DS.accent)
                Spacer(minLength: 8)
                Text(takes.isEmpty ? "NONE" : "\(takes.count) WAITING")
                    .font(.sectionLabel)
                    .tracking(1.2)
                    .foregroundStyle(DS.inkTertiary)
            }
            .padding(.top, 10)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("unfinishedTakesHeader")

            Text("Filmed, never scored. An analysis that stopped, or a run you left. Kept for \(retentionDays) days, then cleared.")
                .font(.footnote)
                .lineSpacing(3)
                .foregroundStyle(DS.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.bottom, 16)

            LaneRule()
                .padding(.bottom, 16)
        }
    }

    private var allClear: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("All clear")
                .font(.grotesk(22, .bold))
                .foregroundStyle(DS.ink)
            Text("Nothing is waiting. Takes land here when a recording never reaches a saved session.")
                .font(.footnote)
                .lineSpacing(3)
                .foregroundStyle(DS.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 28)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("unfinishedTakesAllClear")
    }

    // MARK: - Clear all

    private var clearAllBar: some View {
        VStack(spacing: 0) {
            LaneRule()
            Button {
                confirmingClearAll = true
            } label: {
                Text("DELETE ALL TAKES")
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 11))
                    .tracking(1.4)
                    .foregroundStyle(DS.severityMajor)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Delete all unfinished takes")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .background(DS.background)
    }

    // MARK: - Actions

    private func refresh() {
        // A directory listing over a handful of files — cheap enough to stay
        // synchronous. It is the launch-time *decode* of session blobs that
        // was expensive, and this touches none of that: session membership
        // comes from the stored `id` column the @Query already holds.
        takes = SessionVideoStore.unfinishedTakes(
            referencedIDs: Set(sessions.map(\.id.uuidString)))
    }

    /// Back into the normal pipeline. The take keeps its own id, so the stored
    /// file keeps its name and the session this produces claims it — see
    /// `SessionVideoStore.pendingClip(for:)`.
    private func analyze(_ take: UnfinishedTakes.Take) {
        Haptics.tap()
        router.push(.analyzing(SessionVideoStore.pendingClip(for: take)))
    }

    private func delete(_ take: UnfinishedTakes.Take) {
        Haptics.tap()
        SessionVideoStore.delete(take)
        takes.removeAll { $0.id == take.id }
    }

    private func clearAll() {
        takes.forEach(SessionVideoStore.delete)
        takes = []
    }
}

// MARK: - Take card

/// One unfinished take: poster frame, when it was filmed, and the two answers.
///
/// The leading ochre edge is the same mark `AnalyzingView` stamps on a failed
/// run — on a meet sheet, a swim that did not count. Both the poster frame and
/// the duration come from a single asset load per row, started when the row
/// appears, so a list of takes does not decode every clip up front.
private struct TakeCard: View {
    let take: UnfinishedTakes.Take
    let onAnalyze: () -> Void
    let onDelete: () -> Void

    @State private var poster: UIImage?
    @State private var duration: Double = 0

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useKB]
        return formatter
    }()

    private var dayStamp: String {
        take.capturedAt
            .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            .uppercased()
    }

    private var timeStamp: String {
        take.capturedAt.formatted(date: .omitted, time: .shortened)
    }

    private var detail: String {
        let size = Self.sizeFormatter.string(fromByteCount: take.byteCount)
        return duration > 0 ? "\(ClipTime.code(duration)) · \(size)" : size
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                thumbnail

                VStack(alignment: .leading, spacing: 4) {
                    Text(dayStamp)
                        .font(.sectionLabel)
                        .tracking(1.2)
                        .foregroundStyle(DS.inkTertiary)
                    Text(timeStamp)
                        .font(.grotesk(18, .bold))
                        .foregroundStyle(DS.ink)
                    Text(detail)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(DS.inkSecondary)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Take filmed \(dayStamp), \(timeStamp). \(detail).")

            Rectangle().fill(DS.border).frame(height: 1)

            actions
        }
        .glassCard()
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                .fill(DS.severityModerate)
                .frame(width: 3)
                .accessibilityHidden(true)
        }
        .task { await load() }
    }

    /// Fixed screening band, `scaledToFit` on black — the same treatment
    /// `ReviewView` gives a clip, so portrait and landscape takes sit in the
    /// same rhythm instead of resizing the row.
    private var thumbnail: some View {
        ZStack {
            Color.black
            if let poster {
                Image(uiImage: poster)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
        }
        .frame(width: 104, height: 74)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DS.border, lineWidth: 1))
        .accessibilityHidden(true)
    }

    /// Analyze takes the greedy half of the row and Delete a fixed slot: two
    /// equal-width buttons would read as two equal answers, and the point of
    /// keeping the take is that the user probably still wants it scored.
    private var actions: some View {
        HStack(spacing: 0) {
            Button(action: onAnalyze) {
                HStack(spacing: 6) {
                    Text("ANALYZE")
                        .font(.custom(GroteskWeight.medium.postScriptName, size: 11))
                        .tracking(1.4)
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(DS.accent)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Analyze the take from \(dayStamp) at \(timeStamp)")

            Rectangle().fill(DS.border).frame(width: 1, height: 26)

            Button(role: .destructive, action: onDelete) {
                Text("DELETE")
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 11))
                    .tracking(1.4)
                    .foregroundStyle(DS.severityMajor)
                    .frame(width: 96)
                    .frame(minHeight: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Delete the take from \(dayStamp) at \(timeStamp)")
        }
    }

    /// Duration and poster frame in one pass over the asset.
    ///
    /// The frame is pulled a second in (or mid-clip, whichever is earlier) —
    /// frame zero of a pool recording is usually the deck swinging into place.
    /// The tolerance is deliberately loose: an exact seek forces a decode back
    /// to the previous keyframe for a picture nobody inspects at 104pt.
    @MainActor private func load() async {
        guard poster == nil,
              let url = SessionVideoStore.url(forFileName: take.fileName) else { return }
        let asset = AVURLAsset(url: url)
        if let seconds = try? await asset.load(.duration).seconds, seconds.isFinite {
            duration = seconds
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        let at = CMTime(seconds: duration > 0 ? min(1.0, duration / 2) : 0,
                        preferredTimescale: 600)
        guard let image = try? await generator.image(at: at).image else { return }
        poster = UIImage(cgImage: image)
    }
}
