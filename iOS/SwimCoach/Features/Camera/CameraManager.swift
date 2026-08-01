import AVFoundation
import UIKit

// No @MainActor on the class — all UI property mutations dispatched to main queue explicitly.
final class CameraManager: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {

    @Published private(set) var isRecording = false
    @Published private(set) var recordedVideoURL: URL?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isReady = false
    @Published private(set) var recordingDuration: TimeInterval = 0

    private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    private let session      = AVCaptureSession()
    private let movieOutput  = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "com.swimcoach.camera.session")
    private var durationTimer: Timer?

    // MARK: - Setup

    func setup() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] videoGranted in
            guard videoGranted else {
                DispatchQueue.main.async {
                    self?.errorMessage = "Camera access required. Enable it in Settings → Privacy."
                }
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                self?.sessionQueue.async { self?.configureSession() }
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video, position: .back),
              let camInput = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(camInput) else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.errorMessage = "Camera unavailable on this device." }
            return
        }
        session.addInput(camInput)

        if let mic = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(micInput) {
            session.addInput(micInput)
        }

        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill

        DispatchQueue.main.async {
            self.previewLayer = layer
            self.isReady = true
        }

        session.startRunning()
    }

    // MARK: - Recording

    func startRecording() {
        guard !movieOutput.isRecording else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        movieOutput.startRecording(to: url, recordingDelegate: self)

        DispatchQueue.main.async {
            self.isRecording = true
            self.recordingDuration = 0
            self.durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                DispatchQueue.main.async { self.recordingDuration += 0.5 }
            }
        }
    }

    func stopRecording() {
        movieOutput.stopRecording()
        DispatchQueue.main.async {
            self.isRecording = false
            self.durationTimer?.invalidate()
            self.durationTimer = nil
        }
    }

    func stop() {
        sessionQueue.async { self.session.stopRunning() }
    }

    // MARK: - AVCaptureFileOutputRecordingDelegate

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo url: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        DispatchQueue.main.async {
            if let error = error {
                self.errorMessage = error.localizedDescription
            } else {
                self.recordedVideoURL = url
            }
        }
    }
}
