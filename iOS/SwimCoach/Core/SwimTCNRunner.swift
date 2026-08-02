import CoreML
import Foundation

// Loads swim_tcn.mlpackage from the app bundle and runs inference.
// The ML model is the app's only detection path — a load failure is a
// fatal analysis error surfaced to the user, not a silent degradation.
final class SwimTCNRunner {
    static let shared = SwimTCNRunner()

    // Must match FeedbackEngine's catalog / ISSUE_LABELS in ml/model.py.
    static let expectedLabelCount = 10

    private let queue  = DispatchQueue(label: "com.swimcoach.tcn", qos: .userInitiated)
    private var _model: MLModel?

    var isAvailable: Bool { queue.sync { _model != nil } }

    private init() {
        queue.async { self.load() }
    }

    private func load() {
        // Xcode compiles .mlpackage → .mlmodelc at build time and copies it into the bundle.
        // Try the pre-compiled form first; fall back to on-device compile for raw .mlpackage.
        let modelURL: URL
        if let compiled = Bundle.main.url(forResource: "swim_tcn", withExtension: "mlmodelc") {
            modelURL = compiled
        } else if let raw = Bundle.main.url(forResource: "swim_tcn", withExtension: "mlpackage") {
            do { modelURL = try MLModel.compileModel(at: raw) } catch {
                AppLog.model.error("Failed to compile model: \(error.localizedDescription)")
                return
            }
        } else {
            AppLog.model.fault("swim_tcn model not in bundle — analysis will fail")
            return
        }
        do {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .cpuAndNeuralEngine
            _model = try MLModel(contentsOf: modelURL, configuration: cfg)
            AppLog.model.info("Model loaded — ML analysis enabled")
        } catch {
            AppLog.model.error("Failed to load model: \(error.localizedDescription)")
        }
    }

    func predict(tensor: MLMultiArray) throws -> [Float] {
        guard let m = queue.sync(execute: { _model }) else {
            throw Err.notAvailable
        }
        let provider = try MLDictionaryFeatureProvider(
            dictionary: ["pose_sequence": MLFeatureValue(multiArray: tensor)]
        )
        let output = try m.prediction(from: provider)
        guard let arr = output.featureValue(for: "issue_probabilities")?.multiArrayValue,
              arr.count == Self.expectedLabelCount else {
            throw Err.badOutput
        }
        return (0..<arr.count).map { Float(truncating: arr[$0]) }
    }

    enum Err: LocalizedError {
        case notAvailable, badOutput
        var errorDescription: String? {
            switch self {
            case .notAvailable: return "ML model not loaded"
            case .badOutput:    return "Unexpected model output"
            }
        }
    }
}
