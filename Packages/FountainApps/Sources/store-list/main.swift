import Foundation
import FountainStoreClient

@main
struct StoreListMain {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        let corpusId = env["CORPUS_ID"] ?? "baseline-patchbay"
        let prefix = env["PREFIX"]
        let collection = env["COLLECTION"] ?? "segments"
        let limit = Int(env["LIMIT"] ?? "200") ?? 200
        let store = resolveStore()
        do {
            var q = Query(mode: nil)
            if let p = prefix, !p.isEmpty {
                let field = (collection == "segments" ? "segmentId" : (collection == "pages" ? "pageId" : "id"))
                q.mode = .prefixScan(field, p)
            }
            q.limit = limit
            let res = try await store.query(corpusId: corpusId, collection: collection, query: q)
            print("# segments total=\(res.total) showing=\(res.documents.count)")
            for data in res.documents {
                if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if collection == "segments" {
                        let seg = (obj["segmentId"] as? String) ?? "<unknown>"
                        let kind = (obj["kind"] as? String) ?? ""
                        let page = (obj["pageId"] as? String) ?? ""
                        print("- \(seg) [kind=\(kind), page=\(page)]")
                    } else if collection == "pages" {
                        let pageId = (obj["pageId"] as? String) ?? "<unknown>"
                        let title = (obj["title"] as? String) ?? ""
                        print("- page \(pageId) [title=\(title)]")
                    } else {
                        print("- doc \(obj)")
                    }
                }
            }
        } catch {
            FileHandle.standardError.write(Data("[store-list] error: \(error)\n".utf8))
        }
    }

    static func resolveStore() -> FountainStoreClient {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
            let url: URL
            if dir.hasPrefix("~") {
                url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true)
            } else { url = URL(fileURLWithPath: dir, isDirectory: true) }
            if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) {
            return FountainStoreClient(client: disk)
        }
        return FountainStoreClient(client: EmbeddedFountainStoreClient())
    }
}
