import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct SecretsSeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }
        var args = Array(CommandLine.arguments.dropFirst())
        var agentId: String? = nil
        var corpusId: String = env["SECRETS_CORPUS_ID"] ?? "secrets"
        var headers: [String: String] = [:]
        var filePath: String? = nil
        func usage(_ code: Int32 = 2) -> Never {
            fputs("usage: secrets-seed --agent-id <fountain.coach/agent/...> [--corpus <secrets>] [--header NAME=VALUE]... [--file headers.json]\n", stderr)
            exit(code)
        }
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--agent-id": if i+1 < args.count { agentId = args[i+1]; i += 2 } else { usage() }
            case "--corpus": if i+1 < args.count { corpusId = args[i+1]; i += 2 } else { usage() }
            case "--header": if i+1 < args.count, let eq = args[i+1].firstIndex(of: "=") {
                let name = String(args[i+1][..<eq])
                let value = String(args[i+1][args[i+1].index(after: eq)...])
                headers[name] = value; i += 2
            } else { usage() }
            case "--file": if i+1 < args.count { filePath = args[i+1]; i += 2 } else { usage() }
            default: i += 1
            }
        }
        guard let agent = agentId, !agent.isEmpty else { usage() }
        if headers.isEmpty, let path = filePath {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let h = obj["headers"] as? [String: String] { headers = h }
                else {
                    var map: [String: String] = [:]
                    for (k, v) in obj { if let s = v as? String { map[k] = s } }
                    headers = map
                }
            }
        }
        guard headers.isEmpty == false else {
            fputs("secrets-seed: no headers provided. Use --header or --file.\n", stderr)
            exit(2)
        }
        let store: FountainStoreClient = {
            if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
                let url = URL(fileURLWithPath: dir, isDirectory: true)
                if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
            }
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) { return FountainStoreClient(client: disk) }
            return FountainStoreClient(client: EmbeddedFountainStoreClient())
        }()
        do { _ = try await store.createCorpus(corpusId, metadata: ["kind": "secrets"]) } catch { /* ignore */ }
        let safeId = agent.replacingOccurrences(of: "/", with: "|")
        let key = "secret:agent:\(safeId)"
        let body: [String: Any] = ["headers": headers]
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted])) ?? Data()
        do {
            try await store.putDoc(corpusId: corpusId, collection: "secrets", id: key, body: data)
        } catch {
            fputs("secrets-seed: failed to write secret: \(error)\n", stderr)
            exit(1)
        }
        print("Seeded secrets → corpus=\(corpusId) id=\(key) headers=\(headers.keys.sorted())")
    }
}
