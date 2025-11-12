import Foundation
import FountainStoreClient

@main
struct StoreDump {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        let corpusId = env["CORPUS_ID"] ?? "baseline-patchbay"
        // Generic collection/id support; defaults preserved for segments
        let collection = env["COLLECTION"] ?? "segments"
        let id = env["ID"] ?? env["SEGMENT_ID"] ?? "prompt:baseline-robot-mrts:facts"
        let store = resolveStore()
        do {
            if let data = try await store.getDoc(corpusId: corpusId, collection: collection, id: id) {
                // Try to pretty-print JSON if possible; otherwise, raw string
                if let obj = try? JSONSerialization.jsonObject(with: data),
                   JSONSerialization.isValidJSONObject(obj),
                   let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) {
                    if let s = String(data: pretty, encoding: .utf8) { print(s) }
                    else if let s = String(data: data, encoding: .utf8) { print(s) }
                    else { FileHandle.standardError.write(Data("[store-dump] non-utf8 body\n".utf8)) }
                } else if let s = String(data: data, encoding: .utf8) {
                    // For segments, extract .text when present
                    if collection == "segments",
                       let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any],
                       let text = obj["text"] as? String {
                        print(text)
                    } else { print(s) }
                } else { FileHandle.standardError.write(Data("[store-dump] non-utf8 body\n".utf8)) }
            } else {
                FileHandle.standardError.write(Data("[store-dump] doc not found corpus=\(corpusId) collection=\(collection) id=\(id)\n".utf8))
            }
        } catch {
            FileHandle.standardError.write(Data("[store-dump] error: \(error)\n".utf8))
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
