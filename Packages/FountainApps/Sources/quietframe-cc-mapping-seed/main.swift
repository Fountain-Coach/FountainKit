import Foundation
import FountainStoreClient

@main
struct QuietFrameCCMappingSeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        let corpusId = env["CORPUS_ID"] ?? "quietframe"
        let root = URL(fileURLWithPath: env["FOUNTAINSTORE_DIR"] ?? ".fountain/store")
        let client: FountainStoreClient
        do { client = FountainStoreClient(client: try DiskFountainStoreClient(rootDirectory: root)) }
        catch { print("seed: failed to init DiskFountainStoreClient: \(error)"); return }
        // Ensure corpus exists
        do { _ = try await client.createCorpus(corpusId, metadata: ["app": "quietframe", "kind": "mapping"]) } catch { }

        let pageId = "docs:quietframe:cc-mapping"
        _ = try? await client.addPage(.init(corpusId: corpusId, pageId: pageId, url: "store://docs/quietframe/cc-mapping", host: "store", title: "QuietFrame — CC Mapping"))

        let mapping = """
        { "cc": [
            { "number": 1,  "param": "engine.masterGain", "min": 0.0, "max": 1.0 },
            { "number": 7,  "param": "engine.masterGain", "min": 0.0, "max": 1.0 },
            { "number": 74, "param": "drone.lpfHz",      "min": 300,  "max": 3300 }
        ]}
        """
        _ = try? await client.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):doc", pageId: pageId, kind: "doc", text: mapping))
        print("Seeded CC mapping → corpus=\(corpusId) page=\(pageId)")
    }
}

