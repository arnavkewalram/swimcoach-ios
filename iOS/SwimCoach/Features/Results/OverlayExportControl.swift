import SwiftUI
import Observation

// MARK: - Overlay export: state box + the one control that reads it
//
// This state used to be `@State` on `ResultsView`, read deep inside its body
// via videoSection → videoControls → exportControl. Every progress write
// therefore re-evaluated the ENTIRE Results body — score panel, video section,
// issue rows, tips, footer — because that is the granularity `@State` on the
// root view invalidates at. v1.45.6 throttled the exporter to ≤101 callbacks,
// which cut how often that happened but not what it touched.
//
// Splitting the state into an `@Observable` box fixes the blast radius:
// SwiftUI's observation tracking registers a dependency only where a property
// is actually read during a body evaluation. `ResultsView.body` passes the box
// along without reading `state`, so a progress tick now invalidates
// `OverlayExportControl` alone.
//
// The box (not the control) owns the export task so `ResultsView.onDisappear`
// can still cancel it without depending on a child's onDisappear firing.

/// Export state for the skeleton-overlay video, in a box of its own so that
/// progress ticks invalidate only the control that renders them.
@Observable
final class OverlayExportModel {

    enum State: Equatable {
        case idle, exporting(Double), ready(URL), failed
    }

    private(set) var state: State = .idle

    /// Not observed: nothing renders the task, and publishing it would put
    /// every start/finish back into whatever body last read it.
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Burn the skeleton into the clip. Progress arrives already throttled to
    /// whole percents by `OverlayVideoExporter`; this only hops it to the main
    /// actor. The `.exporting` guard keeps a late tick from resurrecting a run
    /// that has already finished, failed or been cancelled.
    func start(videoURL: URL, frames: [KeypointFrame]) {
        state = .exporting(0)
        task = Task { @MainActor in
            do {
                let out = try await OverlayVideoExporter.export(videoURL: videoURL, frames: frames) { p in
                    Task { @MainActor in
                        guard case .exporting = self.state else { return }
                        self.state = .exporting(p)
                    }
                }
                state = .ready(out)
            } catch is CancellationError {
                state = .idle
            } catch {
                AppLog.storage.error("Overlay export failed: \(error.localizedDescription)")
                state = .failed
            }
        }
    }

    /// Called when Results goes away. The exporter unwinds through its own
    /// cancellation handler and the `catch is CancellationError` branch above
    /// returns the box to `.idle`.
    func cancel() {
        task?.cancel()
    }
}

/// The EXPORT / n% / SHARE VIDEO control. The only view that reads
/// `OverlayExportModel.state`, and therefore the only one a progress tick
/// re-renders.
struct OverlayExportControl: View {
    let model: OverlayExportModel
    let videoURL: URL
    let frames: [KeypointFrame]

    var body: some View {
        switch model.state {
        case .idle, .failed:
            Button {
                model.start(videoURL: videoURL, frames: frames)
            } label: {
                Text(model.state == .failed ? "RETRY EXPORT" : "EXPORT")
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
}
