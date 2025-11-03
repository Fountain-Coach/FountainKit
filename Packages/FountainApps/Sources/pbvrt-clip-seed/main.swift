import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct PBVRTClipSeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }

        var args = CommandLine.arguments.dropFirst().makeIterator()
        var baselineId: String? = nil
        var corpus = env["CORPUS_ID"] ?? "pb-vrt"
        while let a = args.next() {
            switch a {
            case "--baseline-id": baselineId = args.next()
            case "--corpus": if let c = args.next() { corpus = c }
            default: break
            }
        }
        guard let bId = baselineId, !bId.isEmpty else {
            FileHandle.standardError.write(Data("Usage: pbvrt-clip-seed --baseline-id <id> [--corpus <c>]\n".utf8));
            return
        }

        let store: FountainStoreClient = {
            if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
                let url: URL
                if dir.hasPrefix("~") {
                    url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true)
                } else { url = URL(fileURLWithPath: dir, isDirectory: true) }
                if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
            }
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) { return FountainStoreClient(client: disk) }
            return FountainStoreClient(client: EmbeddedFountainStoreClient())
        }()

        let art = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".fountain/artifacts/pb-vrt/\(bId)", isDirectory: true)
        let adh = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".fountain/artifacts/pb-vrt/ad-hoc", isDirectory: true)

        func latest(_ name: String) -> String? {
            guard let contents = try? FileManager.default.contentsOfDirectory(at: adh, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }
            let cand = contents.compactMap { url -> (Date, URL)? in
                let f = url.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: f.path) {
                    let d = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                    return (d, f)
                }
                return nil
            }.sorted { $0.0 < $1.0 }.last?.1
            return cand?.path
        }

        let scenes: [[String: Any]] = [
            ["id":"baseline",  "label":"Baseline",  "uri": art.appendingPathComponent("baseline.png").path,  "durationMs": 1200],
            ["id":"candidate", "label":"Candidate", "uri": art.appendingPathComponent("candidate.png").path, "durationMs": 800],
            ["id":"aligned",   "label":"Aligned",   "uri": latest("aligned.png") as Any,                  "durationMs": 800],
            ["id":"delta",     "label":"Delta",     "uri": (FileManager.default.fileExists(atPath: art.appendingPathComponent("delta.png").path) ? art.appendingPathComponent("delta.png").path : art.appendingPathComponent("delta_full.png").path), "durationMs": 800],
            ["id":"saliency",  "label":"Saliency",  "uris": [latest("baseline-saliency.png") as Any, latest("candidate-saliency.png") as Any, latest("weighted-delta.png") as Any], "durationMs": 800]
        ]
        let clip: [String: Any] = [
            "title": "PB‑VRT Demo Clip",
            "baselineId": bId,
            "scenes": scenes
        ]
        let pageId = "pbvrt:baseline:\(bId)"
        _ = try? await store.addPage(.init(corpusId: corpus, pageId: pageId, url: "store://\(pageId)", host: "store", title: "PBVRT Baseline \(bId)"))
        if let data = try? JSONSerialization.data(withJSONObject: clip, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) {
            _ = try? await store.addSegment(.init(corpusId: corpus, segmentId: "\(pageId):teatro.clip", pageId: pageId, kind: "teatro.clip", text: text))
        }
        print("Seeded teatro.clip for baseline=\(bId) in corpus=\(corpus)")
    }
}

