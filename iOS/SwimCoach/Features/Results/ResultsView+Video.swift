import SwiftUI
import AVKit

// MARK: - ResultsView · session video, skeleton overlay, share/export
//
// Moved verbatim from ResultsView.swift in the 1.36–1.42 code-health pass.
// State lives on ResultsView; these members only read/write it.

extension ResultsView {

    enum VideoExportState: Equatable {
        case idle, exporting(Double), ready(URL), failed
    }

    // MARK: - Session video

    func videoSection(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // At extreme type sizes the header row can't fit beside the
            // controls — fall to a vertical stack instead of letting the
            // label break mid-word. The horizontal branch pins its texts
            // to one line (singleLine header + fixedSize controls) so it
            // can genuinely fail to fit; without that, wrapping text lets
            // it satisfy any width and the fallback never engages.
            ViewThatFits(in: .horizontal) {
                HStack {
                    SectionHeader(title: videoSectionTitle, singleLine: true)
                    HStack { videoControls }
                        .fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: videoSectionTitle)
                    HStack { videoControls }
                }
            }
            ZStack {
                if let player {
                    VideoPlayer(player: player)
                    if showSkeleton, let frames = result.keypointFrames, !frames.isEmpty {
                        SkeletonOverlayView(player: player, frames: frames,
                                            videoSize: videoNaturalSize)
                    }
                } else {
                    Color.black
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.border, lineWidth: 1))
            .accessibilityLabel("Analyzed swim video with detected joint overlay. Review your stroke alongside the feedback below.")

            // Hides itself for legacy sessions (nil windows/duration).
            IssueTimelineStrip(
                windows: result.issueWindows,
                issues: result.issues,
                durationSeconds: result.durationSeconds,
                onSeek: { time in seek(to: time) }
            )
        }
        .id(videoSectionID)
    }

    var hasSkeletonData: Bool {
        !(result.keypointFrames?.isEmpty ?? true)
    }

    var videoSectionTitle: String {
        result.durationText.map { "Video · \($0)" } ?? "Session video"
    }

    @ViewBuilder
    var videoControls: some View {
        shareCardControl
        if hasSkeletonData {
            Button {
                showSkeleton.toggle()
            } label: {
                Text(showSkeleton ? "HIDE JOINTS" : "SHOW JOINTS")
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                    .tracking(1.2)
                    .foregroundStyle(showSkeleton ? DS.accent : DS.inkTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(showSkeleton ? DS.accent.opacity(0.5) : DS.border, lineWidth: 1))
            }
            .accessibilityLabel(showSkeleton ? "Hide detected joints overlay" : "Show detected joints overlay")

            exportControl
        }
    }

    /// The formatted content of the square social card — swimmer/name come
    /// from the saved session when there is one.
    var shareCardModel: ShareCardModel {
        let saved = savedSessions.first
        return ShareCardModel(result: result,
                              swimmer: saved?.swimmer ?? "",
                              sessionName: saved?.name ?? "")
    }

    /// Share the square session summary card — sits with the video export
    /// controls and shares their compact bordered style.
    @ViewBuilder
    var shareCardControl: some View {
        if let shareCardImage {
            ShareLink(
                item: Image(uiImage: shareCardImage),
                preview: SharePreview(shareCardModel.previewTitle,
                                      image: Image(uiImage: shareCardImage))
            ) {
                Text("SHARE CARD")
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                    .tracking(1.2)
                    .foregroundStyle(DS.inkSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(DS.border, lineWidth: 1))
            }
            .accessibilityLabel("Share session summary card")
        }
    }

    @ViewBuilder
    var exportControl: some View {
        switch exportState {
        case .idle, .failed:
            Button {
                startExport()
            } label: {
                Text(exportState == .failed ? "RETRY EXPORT" : "EXPORT")
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                    .tracking(1.2)
                    .foregroundStyle(DS.inkSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(DS.border, lineWidth: 1))
            }
            .accessibilityLabel("Export video with skeleton overlay")
        case .exporting(let p):
            Text("\(Int(p * 100))%")
                .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                .tracking(1.2)
                .foregroundStyle(DS.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(DS.accent.opacity(0.4), lineWidth: 1))
                .accessibilityLabel("Exporting video, \(Int(p * 100)) percent")
        case .ready(let url):
            ShareLink(item: url) {
                Text("SHARE VIDEO")
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                    .tracking(1.2)
                    .foregroundStyle(DS.onAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(DS.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .accessibilityLabel("Share exported video")
        }
    }

    func startExport() {
        guard let url = result.videoURL, let frames = result.keypointFrames else { return }
        exportState = .exporting(0)
        exportTask = Task {
            do {
                let out = try await OverlayVideoExporter.export(videoURL: url, frames: frames) { p in
                    Task { @MainActor in
                        if case .exporting = exportState { exportState = .exporting(p) }
                    }
                }
                await MainActor.run { exportState = .ready(out) }
            } catch is CancellationError {
                await MainActor.run { exportState = .idle }
            } catch {
                AppLog.storage.error("Overlay export failed: \(error.localizedDescription)")
                await MainActor.run { exportState = .failed }
            }
        }
    }
}
