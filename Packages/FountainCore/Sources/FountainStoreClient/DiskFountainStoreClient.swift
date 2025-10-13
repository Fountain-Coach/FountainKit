import Foundation
import FountainStore

/// File-backed implementation of ``FountainStoreClientProtocol``.
///
/// Documents are stored on disk inside a [`FountainStore`](https://github.com/Fountain-Coach/Fountain-Store)
/// instance per corpus, so chat sessions survive process restarts.
public final actor DiskFountainStoreClient: FountainStoreClientProtocol {
    private struct StoredDocument: Codable, Identifiable {
        var id: String
        var payload: Data
    }

    private let rootDirectory: URL
    private let metadataURL: URL
    private var corporaMetadata: [String: [String: String]] = [:]
    private var stores: [String: FountainStore] = [:]

    private let fileManager = FileManager.default
    private let capabilitiesValue = Capabilities(
        corpus: true,
        documents: ["upsert", "get", "delete"],
        query: ["byId", "byIndexEq", "prefixScan", "filters", "sort", "text"],
        transactions: [],
        admin: ["health", "backup", "compaction", "metrics"],
        experimental: []
    )

    public init(rootDirectory: URL) throws {
        var normalized = rootDirectory
        if !normalized.hasDirectoryPath {
            normalized.appendPathComponent("")
        }
        self.rootDirectory = normalized
        self.metadataURL = normalized.appendingPathComponent("corpora.json", isDirectory: false)
        try fileManager.createDirectory(at: normalized, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: metadataURL),
           let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            corporaMetadata = decoded
        }
    }

    // MARK: - Corpus helpers

    private func store(for corpusId: String) async throws -> FountainStore {
        if let existing = stores[corpusId] {
            return existing
        }
        let corpusPath = rootDirectory.appendingPathComponent(corpusId, isDirectory: true)
        try fileManager.createDirectory(at: corpusPath, withIntermediateDirectories: true)
        let store = try await FountainStore.open(.init(path: corpusPath))
        stores[corpusId] = store
        return store
    }

    private func persistMetadata() throws {
        let data = try JSONEncoder().encode(corporaMetadata)
        try data.write(to: metadataURL, options: .atomic)
    }

    private func ensureCorpusMetadataExists(_ corpusId: String) {
        if corporaMetadata[corpusId] == nil {
            corporaMetadata[corpusId] = [:]
            try? persistMetadata()
        }
    }

    // MARK: - Corpus API

    public func createCorpus(id: String, metadata: [String: String]) async throws {
        ensureCorpusMetadataExists(id)
        corporaMetadata[id] = metadata
        try persistMetadata()
        _ = try await store(for: id)
    }

    public func getCorpus(id: String) async throws -> Corpus? {
        if let meta = corporaMetadata[id] {
            return Corpus(id: id, metadata: meta)
        }
        let corpusPath = rootDirectory.appendingPathComponent(id, isDirectory: true)
        guard fileManager.fileExists(atPath: corpusPath.path) else { return nil }
        corporaMetadata[id] = [:]
        try persistMetadata()
        return Corpus(id: id, metadata: [:])
    }

    public func deleteCorpus(id: String) async throws {
        stores[id] = nil
        corporaMetadata.removeValue(forKey: id)
        try persistMetadata()
        let corpusPath = rootDirectory.appendingPathComponent(id, isDirectory: true)
        if fileManager.fileExists(atPath: corpusPath.path) {
            try fileManager.removeItem(at: corpusPath)
        }
    }

    public func listCorpora(limit: Int, offset: Int) async throws -> (total: Int, corpora: [String]) {
        let ids = Array(corporaMetadata.keys).sorted()
        let total = ids.count
        let slice = Array(ids.dropFirst(min(offset, total)).prefix(limit))
        return (total, slice)
    }

    // MARK: - Documents

    public func putDoc(corpusId: String, collection: String, id: String, body: Data) async throws {
        let store = try await store(for: corpusId)
        let coll = await store.collection(collection, of: StoredDocument.self)
        try await coll.put(StoredDocument(id: id, payload: body))
    }

    public func getDoc(corpusId: String, collection: String, id: String) async throws -> Data? {
        let store = try await store(for: corpusId)
        let coll = await store.collection(collection, of: StoredDocument.self)
        if let doc = try await coll.get(id: id) {
            return doc.payload
        }
        return nil
    }

    public func deleteDoc(corpusId: String, collection: String, id: String) async throws {
        let store = try await store(for: corpusId)
        let coll = await store.collection(collection, of: StoredDocument.self)
        try await coll.delete(id: id)
    }

    public func query(corpusId: String, collection: String, query: Query) async throws -> QueryResponse {
        let store = try await store(for: corpusId)
        let coll = await store.collection(collection, of: StoredDocument.self)

        var docs: [StoredDocument] = []
        switch query.mode {
        case .byId(let docId):
            if let hit = try await coll.get(id: docId) {
                docs = [hit]
            }
        case .byIndexEq, .prefixScan, .none:
            docs = try await coll.scan(prefix: nil, limit: nil)
        }

        struct AnnotatedDoc {
            var doc: StoredDocument
            var json: [String: Any]
        }

        let annotated: [AnnotatedDoc] = docs.compactMap { doc in
            let json = decodeJSON(doc.payload)
            return AnnotatedDoc(doc: doc, json: json)
        }

        var filtered = annotated

        if case .byIndexEq(let field, let value) = query.mode {
            filtered = filtered.filter { extractString(field, from: $0.json)?.caseInsensitiveCompare(value) == .orderedSame }
        }
        if case .prefixScan(let field, let prefix) = query.mode {
            filtered = filtered.filter { extractString(field, from: $0.json)?.hasPrefix(prefix) == true }
        }

        if !query.filters.isEmpty {
            filtered = filtered.filter { doc in
                query.filters.allSatisfy { key, expected in
                    guard let actual = extractString(key, from: doc.json) else { return false }
                    return actual == expected
                }
            }
        }

        if let text = query.text, !text.isEmpty {
            let needle = text.lowercased()
            filtered = filtered.filter { doc in
                collectStrings(in: doc.json).contains { $0.contains(needle) }
            }
        }

        if let firstSort = query.sort.first {
            filtered.sort { lhs, rhs in
                let left = extractString(firstSort.field, from: lhs.json) ?? ""
                let right = extractString(firstSort.field, from: rhs.json) ?? ""
                return firstSort.ascending ? (left < right) : (left > right)
            }
        }

        let total = filtered.count
        let offset = min(query.offset ?? 0, max(0, total - 1))
        let limited: [AnnotatedDoc]
        if let limit = query.limit {
            limited = Array(filtered.dropFirst(offset).prefix(limit))
        } else {
            limited = Array(filtered.dropFirst(offset))
        }

        let payloads = limited.map { $0.doc.payload }
        return QueryResponse(total: total, documents: payloads)
    }

    // MARK: - Capabilities

    public func capabilities() async throws -> Capabilities {
        capabilitiesValue
    }

    // MARK: - Admin

    public func snapshot(corpusId: String) async throws {
        throw PersistenceError.notSupported(need: "transactions.snapshot")
    }

    public func restore(corpusId: String) async throws {
        throw PersistenceError.notSupported(need: "transactions.restore")
    }

    public func backup(corpusId: String) async throws {
        throw PersistenceError.notSupported(need: "admin.backup")
    }

    public func compaction(corpusId: String) async throws {
        throw PersistenceError.notSupported(need: "admin.compaction")
    }

    // MARK: - Helpers

    private func decodeJSON(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private func extractString(_ key: String, from json: [String: Any]) -> String? {
        guard !key.isEmpty else { return nil }
        let components = key.split(separator: ".").map(String.init)
        var current: Any = json
        for part in components {
            if let dict = current as? [String: Any], let next = dict[part] {
                current = next
            } else {
                return nil
            }
        }
        if let str = current as? String { return str }
        if let num = current as? NSNumber { return num.stringValue }
        return nil
    }

    private func collectStrings(in json: [String: Any]) -> [String] {
        var bucket: [String] = []
        func walk(_ value: Any) {
            switch value {
            case let dict as [String: Any]:
                dict.values.forEach { walk($0) }
            case let array as [Any]:
                array.forEach { walk($0) }
            case let str as String:
                bucket.append(str.lowercased())
            case let num as NSNumber:
                bucket.append(num.stringValue.lowercased())
            default:
                break
            }
        }
        walk(json)
        return bucket
    }
}
