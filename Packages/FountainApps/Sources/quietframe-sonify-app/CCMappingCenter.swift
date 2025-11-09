import Foundation
import FountainStoreClient

@MainActor final class CCMappingCenter {
    static let shared = CCMappingCenter()
    private var mapping: [Int: Entry] = [:]

    struct Root: Decodable { let cc: [Entry] }
    struct Entry: Decodable { let number: Int; let param: String; let min: Double?; let max: Double? }

    func load() async {
        let env = ProcessInfo.processInfo.environment
        let corpus = env["CORPUS_ID"] ?? "quietframe"
        let root = URL(fileURLWithPath: env["FOUNTAINSTORE_DIR"] ?? ".fountain/store")
        guard let client = try? DiskFountainStoreClient(rootDirectory: root) else { return }
        let store = FountainStoreClient(client: client)
        let segId = "docs:quietframe:cc-mapping:doc"
        if let data = try? await store.getDoc(corpusId: corpus, collection: "segments", id: segId),
           let outer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let text = outer["text"] as? String,
           let innerData = text.data(using: .utf8) {
            if let root = try? JSONDecoder().decode(Root.self, from: innerData) {
                var table: [Int: Entry] = [:]
                for e in root.cc { table[e.number] = e }
                self.mapping = table
                #if DEBUG
                print("[cc-mapping] loaded entries=\(table.count)")
                #endif
                return
            }
        }
        #if DEBUG
        print("[cc-mapping] no mapping found; using defaults")
        #endif
        mapping = [:]
    }

    func mappedParam(for cc: Int, value7: UInt8) -> (name: String, value: Double)? {
        guard let e = mapping[cc] else { return nil }
        let t = Double(value7) / 127.0
        if let min = e.min, let max = e.max { return (e.param, min + t * (max - min)) }
        return (e.param, t)
    }
}

