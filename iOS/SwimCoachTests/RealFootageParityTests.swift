import XCTest
import CoreML
@testable import SwimCoach

// Cross-platform parity on REAL footage: keypoint windows extracted from
// Creative-Commons swimming clips (MediaPipe, model convention) must produce
// the same probabilities through the app's CoreML path as the PyTorch
// reference produced on the Python side. This is the guard that would have
// caught the y-axis flip and the missing-sigmoid bugs automatically.
final class RealFootageParityTests: XCTestCase {

    private func tensor(fromCSV csv: String) throws -> MLMultiArray {
        let values = csv.split(separator: ",").map { Float($0)! }
        XCTAssertEqual(values.count, 39 * 90, "fixture must be one (39, 90) window")
        let arr = try MLMultiArray(shape: [1, 39, 90], dataType: .float32)
        let ptr = arr.dataPointer.assumingMemoryBound(to: Float32.self)
        for (i, v) in values.enumerated() { ptr[i] = v }
        return arr
    }

    func testRealFootagePredictionsMatchPythonReference() throws {
        for fixture in RealFootageFixtures.all {
            let input = try tensor(fromCSV: fixture.tensorCSV)
            let probs = try SwimTCNRunner.shared.predict(tensor: input)
            XCTAssertEqual(probs.count, fixture.expected.count, fixture.name)
            for (i, (got, want)) in zip(probs, fixture.expected).enumerated() {
                XCTAssertEqual(got, want, accuracy: 0.001,
                               "\(fixture.name) label \(i): app=\(got) python=\(want)")
            }
        }
    }

    func testRealFootageDecodedIssuesMatchPythonReference() throws {
        for fixture in RealFootageFixtures.all {
            let input = try tensor(fromCSV: fixture.tensorCSV)
            let probs = try SwimTCNRunner.shared.predict(tensor: input)
            let appIssues = Set(FeedbackEngine.decode(probabilities: probs).map(\.name))
            let refIssues = Set(FeedbackEngine.decode(probabilities: fixture.expected).map(\.name))
            XCTAssertEqual(appIssues, refIssues, fixture.name)
        }
    }
}
