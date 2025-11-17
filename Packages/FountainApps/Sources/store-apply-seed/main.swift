import Foundation
import FountainStoreClient

@main
struct StoreApplySeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        let corpus = env["CORPUS_ID"] ?? "agents"
        let seedDir = env["SEED_DIR"] ?? "Dist/store-seeds/seed-v1"
        let out = FileHandle.standardError

        // Resolve store
        let store: FountainStoreClient = {
            if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
                let url = URL(fileURLWithPath: dir, isDirectory: true)
                if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
            }
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) { return FountainStoreClient(client: disk) }
            return FountainStoreClient(client: EmbeddedFountainStoreClient())
        }()

        let seedURL = URL(fileURLWithPath: seedDir, isDirectory: true)
        let agentFactsDir = seedURL.appendingPathComponent("agents/agent-facts", isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(at: agentFactsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            out.write(Data("[store-apply-seed] ERROR: seed not found at \(agentFactsDir.path)\n".utf8))
            exit(2)
        }
        var applied = 0
        for url in items where url.pathExtension.lowercased() == "json" {
            var id = url.lastPathComponent
            if id.hasSuffix(".json") { id.removeLast(5) }
            do {
                let data = try Data(contentsOf: url)
                try await store.putDoc(corpusId: corpus, collection: "agent-facts", id: id, body: data)
                applied += 1
            } catch {
                out.write(Data("[store-apply-seed] WARN: failed to apply \(id): \(error)\n".utf8))
            }
        }
        out.write(Data("[store-apply-seed] applied \(applied) documents into corpus=\(corpus)\n".utf8))
    }
}
