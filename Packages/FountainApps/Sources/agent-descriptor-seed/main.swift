import Foundation
import FountainStoreClient
import Yams
import Crypto

@main
struct AgentDescriptorSeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        let file = CommandLine.arguments.dropFirst().first ?? env["AGENT_FILE"]
        guard let file else {
            fputs("usage: agent-descriptor-seed <descriptor.(yaml|json)>\n", stderr)
            exit(2)
        }
        let corpusId = env["AGENT_CORPUS_ID"] ?? env["CORPUS_ID"] ?? "agents"
        let root = URL(fileURLWithPath: env["FOUNTAINSTORE_DIR"] ?? ".fountain/store")
        let store: FountainStoreClient
        do { store = FountainStoreClient(client: try DiskFountainStoreClient(rootDirectory: root)) } catch {
            fputs("seed: store init failed: \(error)\n", stderr); exit(2)
        }
        do { _ = try await store.createCorpus(corpusId, metadata: ["kind":"agents","seed":"agent-descriptor-seed"]) } catch { }

        // Load descriptor (YAML or JSON)
        let url = URL(fileURLWithPath: file)
        let data = try! Data(contentsOf: url)
        let any: Any
        if file.hasSuffix(".yaml") || file.hasSuffix(".yml") {
            any = try! Yams.load(yaml: String(decoding: data, as: UTF8.self)) as Any
        } else { any = try! JSONSerialization.jsonObject(with: data) }
        guard var desc = any as? [String: Any] else {
            fputs("seed: descriptor is not an object\n", stderr); exit(2)
        }
        // Extract required identity
        guard let agentId = desc["x-agent-id"] as? String, !agentId.isEmpty else {
            fputs("seed: missing x-agent-id\n", stderr); exit(2)
        }
        // Compute key and upsert
        let key = "agent:\(agentId)"
        // Optional signature if missing
        if desc["x-agent-signature"] == nil, let canonical = try? canonicalJSON(desc) {
            let sig = sha256Hex(canonical)
            desc["x-agent-signature"] = sig
        }
        guard let payload = try? JSONSerialization.data(withJSONObject: desc, options: []) else {
            fputs("seed: failed to encode descriptor\n", stderr); exit(2)
        }
        do {
            try await store.putDoc(corpusId: corpusId, collection: "agent-descriptors", id: key, body: payload)
        } catch {
            fputs("seed: write failed: \(error)\n", stderr); exit(3)
        }
        // Update registry index
        do {
            let indexId = "registry:index"
            var ids: [String] = []
            if let existing = try await store.getDoc(corpusId: corpusId, collection: "agent-registry", id: indexId),
               let obj = try? JSONSerialization.jsonObject(with: existing) as? [String: Any],
               let arr = obj["agents"] as? [String] {
                ids = arr
            }
            if !ids.contains(agentId) { ids.append(agentId) }
            let indexObj: [String: Any] = ["agents": ids.sorted()]
            let indexPayload = try JSONSerialization.data(withJSONObject: indexObj)
            try await store.putDoc(corpusId: corpusId, collection: "agent-registry", id: indexId, body: indexPayload)
        } catch {
            fputs("seed: registry update failed: \(error)\n", stderr)
        }
        print("seeded: corpus=\(corpusId) id=\(key)")
    }

    static func canonicalJSON(_ d: [String: Any]) throws -> Data {
        func sorted(_ any: Any) -> Any {
            if let dict = any as? [String: Any] {
                return Dictionary(uniqueKeysWithValues: dict.keys.sorted().map { ($0, sorted(dict[$0]!)) })
            } else if let arr = any as? [Any] {
                return arr.map(sorted(_:))
            }
            return any
        }
        return try JSONSerialization.data(withJSONObject: sorted(d))
    }

    static func sha256Hex(_ data: Data) -> String {
        let digest = Crypto.SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
