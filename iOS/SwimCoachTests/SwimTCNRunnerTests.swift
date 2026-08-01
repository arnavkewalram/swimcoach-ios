import XCTest
import CoreML
@testable import SwimCoach

final class SwimTCNRunnerTests: XCTestCase {

    func testSharedSingletonIsSameInstance() {
        XCTAssertTrue(SwimTCNRunner.shared === SwimTCNRunner.shared)
    }

    func testModelLoads() {
        // The ML model is the app's only detection path — it MUST load from the bundle.
        // A failure here means the .mlpackage is missing or broken, which would make
        // every real analysis fail on device.
        XCTAssertTrue(SwimTCNRunner.shared.isAvailable,
                      "swim_tcn model failed to load — ML analysis is mandatory")
    }

    func testPredictReturns10ValuesInRange() throws {
        let shape: [NSNumber] = [1, 39, 90]
        let tensor = try MLMultiArray(shape: shape, dataType: .float32)
        // Fill with small random-ish values matching realistic normalized joint coords
        let ptr = tensor.dataPointer.assumingMemoryBound(to: Float32.self)
        for i in 0..<(39 * 90) { ptr[i] = Float(i % 39) / 39.0 }

        let probs = try SwimTCNRunner.shared.predict(tensor: tensor)
        XCTAssertEqual(probs.count, 10, "Expected 10 probability values (one per issue label)")

        for (i, p) in probs.enumerated() {
            XCTAssertGreaterThanOrEqual(p, 0.0, "prob[\(i)] < 0")
            XCTAssertLessThanOrEqual(p, 1.0, "prob[\(i)] > 1")
            XCTAssertTrue(p.isFinite, "prob[\(i)] is not finite")
        }
    }

    func testPredictWithZeroTensorDoesNotCrash() throws {
        let tensor = try MLMultiArray(shape: [1, 39, 90], dataType: .float32)
        let probs = try SwimTCNRunner.shared.predict(tensor: tensor)
        XCTAssertEqual(probs.count, 10)
    }
}
