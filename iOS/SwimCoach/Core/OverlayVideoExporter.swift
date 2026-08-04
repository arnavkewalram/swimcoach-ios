import AVFoundation
import CoreGraphics
import UIKit

/// Exports a session video with the detected skeleton burned into the
/// frames — shareable proof of what the analysis saw.
/// Frame-accurate: each output frame gets the keypoint frame nearest its
/// presentation time (or nothing during detection gaps).
enum OverlayVideoExporter {

    enum ExportError: LocalizedError {
        case noVideoTrack, cannotStart
        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "The session video has no video track."
            case .cannotStart:  return "Could not start the video export."
            }
        }
    }

    /// Map one keypoint frame into RAW-frame pixel space. Keypoints are
    /// Vision-normalized in display (oriented) space; the exporter draws
    /// on untransformed frames, so each point goes back through the
    /// track transform. Pure — unit-tested.
    static func pixelPoints(for frame: KeypointFrame, naturalSize: CGSize,
                            transform: CGAffineTransform = .identity) -> [CGPoint?] {
        (0..<KeypointFrame.jointCount).map { j -> CGPoint? in
            guard let p = frame.point(j) else { return nil }
            return VideoTransform.rawPixelPoint(
                visionDisplayPoint: CGPoint(x: p.x, y: p.y),
                natural: naturalSize, transform: transform)
        }
    }

    /// Whole-percent bucket for a progress fraction, clamped to 0...100.
    /// Pure — unit-tested.
    static func percentStep(_ fraction: Double) -> Int {
        Int(min(max(fraction, 0), 1) * 100)
    }

    /// Gate for `export`'s progress callback: report only when the whole
    /// percent advances. The encode pump runs once per decoded source frame,
    /// and the caller hops to the main actor on every report — reporting each
    /// raw frame spawned a task per frame (~1800 on a 60s clip) and re-ran the
    /// whole Results body each time, the same trap `PoseAnalyzer` guards with
    /// its sample-rate check. Caps any clip at 101 reports (0...100).
    /// Pure — unit-tested.
    static func shouldReport(fraction: Double, lastReported: Int) -> Bool {
        percentStep(fraction) > lastReported
    }

    /// Stateful side of the whole-percent throttle. The pump block is
    /// `@Sendable`, so the running percent cannot be a captured `var`; it runs
    /// on a single queue but the lock keeps that assumption from being load-bearing.
    final class ProgressThrottle: @unchecked Sendable {
        private let lock = NSLock()
        private var lastReported = -1

        /// True — and advances the gate — when `fraction` crosses into a whole
        /// percent not yet reported. Starts below zero so 0.0 always reports.
        func admit(_ fraction: Double) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard OverlayVideoExporter.shouldReport(fraction: fraction,
                                                    lastReported: lastReported) else { return false }
            lastReported = OverlayVideoExporter.percentStep(fraction)
            return true
        }
    }

    static func export(
        videoURL: URL,
        frames: [KeypointFrame],
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.noVideoTrack
        }
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let duration = try await asset.load(.duration).seconds
        let size = CGSize(width: abs(naturalSize.width), height: abs(naturalSize.height))

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swimcoach-overlay-\(UUID().uuidString).mp4")

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
        ])
        writerInput.expectsMediaDataInRealTime = false
        // Output frames stay raw; carrying the source transform keeps the
        // exported file playing in the same orientation as the original.
        writerInput.transform = preferredTransform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: size.width,
                kCVPixelBufferHeightKey as String: size.height,
            ])
        writer.add(writerInput)

        guard reader.startReading(), writer.startWriting() else {
            throw ExportError.cannotStart
        }
        writer.startSession(atSourceTime: .zero)

        let accent = UIColor(red: 0.043, green: 0.322, blue: 0.863, alpha: 0.9)
        let cancelled = CancelFlag()
        let throttle = ProgressThrottle()
        let queue = DispatchQueue(label: "com.swimcoach.overlay-export")

        // Canonical AVAssetWriter pump: requestMediaDataWhenReady drives the
        // loop at encoder speed. (A readiness-polling sleep loop here made an
        // 8s clip take ~10 minutes — caught by the integration test.)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                writerInput.requestMediaDataWhenReady(on: queue) {
                    while writerInput.isReadyForMoreMediaData {
                        if cancelled.isSet {
                            reader.cancelReading()
                            writer.cancelWriting()
                            writerInput.markAsFinished()
                            cont.resume(throwing: CancellationError())
                            return
                        }
                        guard let sample = readerOutput.copyNextSampleBuffer() else {
                            // Source drained. The last frame's PTS stops a
                            // frame-interval short of the asset duration, so
                            // the throttle would otherwise strand the caller
                            // below 100% — report the terminal value here.
                            if throttle.admit(1.0) { progress(1.0) }
                            writerInput.markAsFinished()
                            writer.finishWriting {
                                if writer.status == .completed {
                                    cont.resume()
                                } else {
                                    cont.resume(throwing: writer.error ?? ExportError.cannotStart)
                                }
                            }
                            return
                        }
                        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                        let pts = CMSampleBufferGetPresentationTimeStamp(sample)

                        CVPixelBufferLockBaseAddress(pixelBuffer, [])
                        if let frame = frames.nearest(to: pts.seconds),
                           let ctx = CGContext(
                                data: CVPixelBufferGetBaseAddress(pixelBuffer),
                                width: CVPixelBufferGetWidth(pixelBuffer),
                                height: CVPixelBufferGetHeight(pixelBuffer),
                                bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                    | CGBitmapInfo.byteOrder32Little.rawValue) {
                            // CG origin is bottom-left over the buffer memory;
                            // flip so our top-left math draws upright.
                            ctx.translateBy(x: 0, y: CGFloat(CVPixelBufferGetHeight(pixelBuffer)))
                            ctx.scaleBy(x: 1, y: -1)
                            draw(frame: frame, in: ctx, naturalSize: size,
                                 transform: preferredTransform, color: accent)
                        }
                        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

                        adaptor.append(pixelBuffer, withPresentationTime: pts)
                        if duration > 0 {
                            let fraction = min(pts.seconds / duration, 1.0)
                            if throttle.admit(fraction) { progress(fraction) }
                        }
                    }
                }
            }
        } onCancel: {
            cancelled.set()
        }

        if cancelled.isSet {
            try? FileManager.default.removeItem(at: outURL)
            throw CancellationError()
        }
        return outURL
    }

    private final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    private static func draw(frame: KeypointFrame, in ctx: CGContext,
                             naturalSize: CGSize, transform: CGAffineTransform,
                             color: UIColor) {
        let points = pixelPoints(for: frame, naturalSize: naturalSize, transform: transform)
        let lineWidth = max(2, min(naturalSize.width, naturalSize.height) / 240)

        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        for (a, b) in KeypointFrame.limbs {
            guard let pa = points[a], let pb = points[b] else { continue }
            ctx.move(to: pa)
            ctx.addLine(to: pb)
            ctx.strokePath()
        }

        let r = max(3, min(naturalSize.width, naturalSize.height) / 180)
        for case let p? in points {
            let dot = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillEllipse(in: dot)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(lineWidth * 0.75)
            ctx.strokeEllipse(in: dot)
        }
    }
}
