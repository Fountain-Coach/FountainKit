import Foundation
import FountainStoreClient

@main
struct OpenAPIFactsStatusMain {
    static func main() async {
        var agentFilter: String?
        var quiet = false
        var i = 1
        let args = CommandLine.arguments
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--agent-id":
                if i + 1 < args.count { agentFilter = args[i + 1]; i += 1 }
            case "--quiet":
                quiet = true
            default:
                break
            }
            i += 1
        }

        do {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let storeDirEnv = ProcessInfo.processInfo.environment["FOUNTAINSTORE_DIR"]
            let storeRoot = storeDirEnv.map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? root.appendingPathComponent(".fountain/store", isDirectory: true)

            let disk = try DiskFountainStoreClient(rootDirectory: storeRoot)
            let client = FountainStoreClient(client: disk)

            let mappingsURL = root.appendingPathComponent("Tools/openapi-facts-mapping.json")
            let data = try Data(contentsOf: mappingsURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw NSError(domain: "openapi-facts-status", code: 1, userInfo: [NSLocalizedDescriptionKey: "invalid mapping JSON"])
            }

            var overallMissing = false

            for entry in json {
                guard let spec = entry["spec"] as? String,
                      let agentId = entry["agentId"] as? String else { continue }
                if let filter = agentFilter, filter != agentId { continue }

                let docId = "facts:agent:" + agentId.replacingOccurrences(of: "/", with: "|")
                let exists = try await client.getDoc(corpusId: "agents", collection: "agent-facts", id: docId) != nil

                if quiet {
                    if !exists { overallMissing = true }
                } else {
                    let status = exists ? "present" : "missing"
                    print("[facts-status] spec=\(spec) agentId=\(agentId) → \(status)")
                }
            }

            if quiet {
                if overallMissing {
                    exit(1)
                } else {
                    exit(0)
                }
            }
        } catch {
            if quiet {
                exit(1)
            } else {
                fputs("openapi-facts-status error: \(error)\n", stderr)
                exit(1)
            }
        }
    }
}

