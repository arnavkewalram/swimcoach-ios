import SwiftUI
import AVFoundation

struct CameraView: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var level = LevelMonitor()
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Recording indicator pulse
    @State private var recPulse = false
    // Tip cycling
    @State private var tipIndex = 0
    @State private var tipVisible = true
    @State private var tipTimer: Timer?

    private let tips = [
        "Film from the side — full body visible",
        "Swim one lap at a normal pace",
        "Keep camera steady at water level",
        "Ensure good lighting above the water"
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Live preview
            if camera.isReady, let layer = camera.previewLayer {
                CameraPreviewView(layer: layer)
                    .ignoresSafeArea()
            } else if camera.errorMessage == nil {
                VStack(spacing: 12) {
                    ProgressView().tint(DS.accent)
                    Text("Starting camera…").foregroundStyle(.secondary)
                }
            }

            // Framing guide (only when not recording)
            if !camera.isRecording {
                framingGuide
            }

            // UI overlay
            VStack(spacing: 0) {
                // Top bar
                topBar
                    .padding(.top, 8)

                if !camera.isRecording, let roll = level.rollDegrees {
                    levelIndicator(roll: roll)
                        .padding(.top, 14)
                        .transition(.opacity)
                }

                Spacer()

                // Tips card
                if !camera.isRecording {
                    tipsCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Record button
                recordButton
                    .padding(.bottom, 44)
            }

            // Error overlay
            if let err = camera.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill.badge.ellipsis")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)
                    Text(err)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding()
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            camera.setup()
            level.start()
            startTipCycling()
        }
        .onDisappear {
            camera.stop()
            level.stop()
            tipTimer?.invalidate()
            tipTimer = nil
        }
        .onChange(of: camera.recordedVideoURL) { _, url in
            guard let url else { return }
            router.push(.analyzing(url))
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close camera")

            Spacer()

            if camera.isRecording {
                HStack(spacing: 8) {
                    // Pulsing red dot (static ring under Reduce Motion)
                    ZStack {
                        Circle()
                            .fill(.red.opacity(reduceMotion ? 0.25 : (recPulse ? 0.35 : 0)))
                            .frame(width: 18, height: 18)
                            .animation(
                                reduceMotion ? nil :
                                    .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                                value: recPulse
                            )
                        Circle()
                            .fill(.red)
                            .frame(width: 9, height: 9)
                    }
                    .onAppear { if !reduceMotion { recPulse = true } }
                    .onDisappear { recPulse = false }

                    Text("REC")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)

                    Text(formatDuration(camera.recordingDuration))
                        .monospacedDigit()
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            Spacer().frame(width: 44)
        }
        .padding(.horizontal, 20)
        .animation(.easeInOut(duration: 0.3), value: camera.isRecording)
    }

    // MARK: - Level indicator

    private func levelIndicator(roll: Double) -> some View {
        let isLevel = LevelMath.isLevel(roll)
        return VStack(spacing: 6) {
            ZStack {
                // Fixed reference horizon
                Rectangle()
                    .fill(.white.opacity(0.35))
                    .frame(width: 64, height: 1)
                // Live horizon, rotating with the device
                Rectangle()
                    .fill(isLevel ? Color(red: 0.30, green: 0.72, blue: 0.46) : .white)
                    .frame(width: 64, height: 2)
                    .rotationEffect(.degrees(-roll))
                    .animation(.linear(duration: 0.1), value: roll)
            }
            .frame(height: 24)

            Text(isLevel ? "LEVEL" : String(format: "%+.0f°", roll))
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isLevel ? Color(red: 0.30, green: 0.72, blue: 0.46) : .white.opacity(0.75))
                .shadow(color: .black.opacity(0.5), radius: 2)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLevel ? "Camera is level" : "Camera tilted \(Int(abs(roll))) degrees")
    }

    // MARK: - Framing guide

    private var framingGuide: some View {
        GeometryReader { geo in
            let w = geo.size.width * 0.75
            let h = geo.size.height * 0.45
            let x = (geo.size.width - w) / 2
            let y = (geo.size.height - h) / 2

            ZStack {
                // Dashed framing rect
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        style: StrokeStyle(lineWidth: 1.5, dash: [8, 5])
                    )
                    .fill(Color.clear)
                    .frame(width: w, height: h)
                    .foregroundStyle(.white.opacity(0.45))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                // Label
                Text("Position swimmer here")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .shadow(color: .black.opacity(0.5), radius: 3)
                    .position(x: geo.size.width / 2, y: y + h + 18)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }

    // MARK: - Tips card

    private var tipsCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.footnote)
                .foregroundStyle(.yellow)
                .padding(8)
                .background(Color.yellow.opacity(0.12))
                .clipShape(Circle())

            Text(tips[tipIndex % tips.count])
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .opacity(tipVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: tipVisible)

            Spacer()
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .background(DS.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DS.border, lineWidth: 1)
        )
    }

    // MARK: - Record button

    private var recordButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                if camera.isRecording { camera.stopRecording() }
                else { camera.startRecording() }
            }
        } label: {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(Color.white.opacity(camera.isRecording ? 0.9 : 0.6), lineWidth: 3)
                    .frame(width: 80, height: 80)

                if camera.isRecording {
                    // Stop square
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.red)
                        .frame(width: 30, height: 30)
                } else {
                    // Record circle
                    Circle()
                        .fill(Color.red)
                        .frame(width: 64, height: 64)
                }
            }
            .shadow(
                color: camera.isRecording ? .red.opacity(0.6) : .clear,
                radius: 20,
                x: 0,
                y: 0
            )
            .animation(.easeInOut(duration: 0.25), value: camera.isRecording)
        }
        .disabled(!camera.isReady)
        .accessibilityLabel(camera.isRecording ? "Stop recording" : "Start recording")
    }

    // MARK: - Helpers

    private func formatDuration(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }

    private func startTipCycling() {
        tipTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [self] _ in
            guard !camera.isRecording else { return }
            withAnimation { tipVisible = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                tipIndex += 1
                withAnimation { tipVisible = true }
            }
        }
    }
}

// UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer
private struct CameraPreviewView: UIViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .black
        layer.frame = v.bounds
        v.layer.addSublayer(layer)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async { layer.frame = uiView.bounds }
    }
}
