import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FountainStoreClient

@main
struct FactsValidate {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        let corpus = env["CORPUS_ID"] ?? "agents"
        guard let agentId = env["AGENT_ID"] else {
            fputs("usage: facts-validate requires AGENT_ID in env\n", stderr)
            exit(2)
        }
        let baseURL = env["AGENT_BASE_URL"].flatMap(URL.init(string:))
        let dryRun = (env["DRY_RUN"] ?? "1") != "0"
        let out = FileHandle.standardError

        // Resolve store
        let store: FountainStoreClient = {
            if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
                let url = URL(fileURLWithPath: dir, isDirectory: true)
                if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
            }
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) {
                return FountainStoreClient(client: disk)
            }
            return FountainStoreClient(client: EmbeddedFountainStoreClient())
        }()

        // Load facts (safe and legacy)
        let safeId = agentId.replacingOccurrences(of: "/", with: "|")
        let keys = ["facts:agent:\(safeId)", "facts:agent:\(agentId)"]
        var factsObj: [String: Any]? = nil
        for key in keys {
            if let data = try? await store.getDoc(corpusId: corpus, collection: "agent-facts", id: key),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                factsObj = obj
                break
            }
        }
        guard let facts = factsObj else {
            fputs("facts-validate: facts not found for agent=\(agentId) corpus=\(corpus)\n", stderr)
            exit(1)
        }
        // Parse properties
        guard let blocks = facts["functionBlocks"] as? [[String: Any]] else {
            fputs("facts-validate: functionBlocks missing\n", stderr)
            exit(1)
        }
        var tested = 0
        for block in blocks {
            guard let props = block["properties"] as? [[String: Any]] else { continue }
            for p in props {
                guard let pid = p["id"] as? String else { continue }
                guard let mapsTo = p["mapsTo"] as? [String: Any], let openapi = mapsTo["openapi"] as? [String: Any], let path = openapi["path"] as? String else { continue }
                let method = (openapi["method"] as? String ?? "GET").uppercased()
                let hasBody = (openapi["body"] as? String == "json")
                tested += 1
                if dryRun { out.write(Data("[facts-validate] mapping id=\(pid) -> \(method) \(path) body=\(hasBody)\n".utf8)); continue }
                guard let base = baseURL else {
                    fputs("facts-validate: AGENT_BASE_URL is required for live check\n", stderr)
                    exit(2)
                }
                // Skip variable paths we can't fill (e.g. /foo/{id})
                if path.contains("{") || path.contains("}") { continue }
                var req = URLRequest(url: base.appendingPathComponent(path))
                req.httpMethod = method
                if hasBody {
                    // Look for sample payload
                    guard let s = p["samples"] as? [String: Any], let r = s["request"] else {
                        // No sample available; skip live validation for this mapping
                        continue
                    }
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let data = try? JSONSerialization.data(withJSONObject: r) { req.httpBody = data }
                }
                // Optional API key for secured services
                if let apiKey = env["API_KEY"] ?? env["FACTS_API_KEY"] { req.setValue(apiKey, forHTTPHeaderField: "X-API-Key") }
                do {
                    let (data, resp) = try await URLSession.shared.data(for: req)
                    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    out.write(Data("[facts-validate] \(pid) -> status=\(status) bytes=\(data.count)\n".utf8))
                } catch {
                    out.write(Data("[facts-validate] ERROR id=\(pid) \(error)\n".utf8))
                    exit(1)
                }
            }
        }
        if tested == 0 { fputs("facts-validate: no mapped properties found\n", stderr); exit(1) }
        print("ok")
    }
}
