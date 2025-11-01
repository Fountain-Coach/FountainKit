import XCTest
@testable import pbvrt_server

final class EmbeddingTests: XCTestCase {
    func testFeatureprintDistanceIdentical() throws {
        // Use an existing PNG in the repo to avoid adding binary fixtures
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).deletingLastPathComponent().deletingLastPathComponent()
        let pngURL = root.appendingPathComponent("Design/a4-tilted-staves-triple.png")
        let data = try Data(contentsOf: pngURL)
        let dist = try PBVRTEngine.featureprintDistance(baseline: data, candidate: data)
        XCTAssertLessThan(dist, 0.001, "FeaturePrint distance should be ~0 for identical images, got \(dist)")
    }
}

