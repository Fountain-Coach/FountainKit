import Foundation
import pbvrt_server
@main
struct PBVRTEmbedCI {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let img = root.appendingPathComponent("Design/a4-tilted-staves-triple.png").path
        let data = try Data(contentsOf: URL(fileURLWithPath: img))
        let dist = try PBVRTEngine.featureprintDistance(baseline: data, candidate: data)
        print(String(format: "featureprint_distance=%.6f", dist))
        if dist > 0.001 { fatalError("distance too high: \(dist)") }
    }
}
