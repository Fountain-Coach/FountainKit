import Foundation
import FountainStoreClient

/// Small helper to upsert an instrument entry into the catalog corpus.
/// Mirrors the logic of `instrument-catalog-server` but runs as a one-shot CLI.
@main
struct InstrumentCatalogSeed {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        func nextValue(flag: String) -> String? {
            guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
            let value = args[idx + 1]
            args.removeSubrange(idx...(idx + 1))
            return value
        }

        guard let id = nextValue(flag: "--id"),
              let title = nextValue(flag: "--title"),
              let agentId = nextValue(flag: "--agent-id")
        else {
            fputs("usage: instrument-catalog-seed --id <id> --title <title> --agent-id <agentId> [--summary <text>] [--group <name>] [--version <v>] [--icon-url <url>]\n", stderr)
            exit(2)
        }
        let summary = nextValue(flag: "--summary")
        let group = nextValue(flag: "--group")
        let version = nextValue(flag: "--version")
        let iconURL = nextValue(flag: "--icon-url")

        let env = ProcessInfo.processInfo.environment
        let corpus = env["CATALOG_CORPUS_ID"] ?? env["CORPUS_ID"] ?? "instruments"

        // Resolve store root from env or default `.fountain/store` under current directory.
        let store: FountainStoreClient = {
            let root: URL
            if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
                if dir.hasPrefix("/") {
                    root = URL(fileURLWithPath: dir, isDirectory: true)
                } else {
                    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                    root = cwd.appendingPathComponent(dir, isDirectory: true)
                }
            } else {
                let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                root = cwd.appendingPathComponent(".fountain/store", isDirectory: true)
            }
            if let disk = try? DiskFountainStoreClient(rootDirectory: root) {
                return FountainStoreClient(client: disk)
            } else {
                return FountainStoreClient(client: EmbeddedFountainStoreClient())
            }
        }()

        do {
            // Upsert instrument document.
            let key = "instrument:\(id)"
            var doc: [String: Any] = [
                "id": id,
                "title": title,
                "agentIds": [agentId],
                "enabled": true
            ]
            if let summary { doc["summary"] = summary }
            if let group { doc["group"] = group }
            if let version { doc["version"] = version }
            if let iconURL { doc["iconURL"] = iconURL }
            let data = try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted])
            try await store.putDoc(corpusId: corpus, collection: "instrument-catalog", id: key, body: data)

            // Update index document.
            var ids: [String] = []
            if let idxData = try? await store.getDoc(corpusId: corpus, collection: "instrument-catalog", id: "instrument-catalog:index"),
               let idxObjAny = try? JSONSerialization.jsonObject(with: idxData),
               let idxObj = idxObjAny as? [String: Any],
               let existing = idxObj["ids"] as? [String] {
                ids = existing
            }
            if !ids.contains(id) { ids.append(id) }
            let idxDoc: [String: Any] = ["ids": ids]
            let idxData = try JSONSerialization.data(withJSONObject: idxDoc, options: [.prettyPrinted])
            try await store.putDoc(corpusId: corpus, collection: "instrument-catalog", id: "instrument-catalog:index", body: idxData)

            fputs("[instrument-catalog-seed] upserted id=\(id) agentId=\(agentId) corpus=\(corpus)\n", stderr)
        } catch {
            fputs("[instrument-catalog-seed] error: \(error)\n", stderr)
            exit(1)
        }
    }
}

