import Foundation

/// Simple in-memory implementation of ``FountainStoreClientProtocol``.
///
/// This client is meant for tests only. Documents are kept inside process
/// memory and therefore disappear once the instance is deallocated.
public final actor EmbeddedFountainStoreClient: FountainStoreClientProtocol {
    /// corpusId -> collection -> docId -> Data
    private var docs: [String: [String: [String: Data]]] = [:]
    private var corpusMeta: [String: [String: String]] = [:]
    private var snapshots: [String: [String: [String: Data]]] = [:]
    private let caps: Capabilities

    public init(caps: Capabilities = Capabilities(
        corpus: true,
        documents: ["upsert", "get", "delete"],
        query: ["byId", "byIndexEq", "prefixScan", "filters", "sort"],
        transactions: ["snapshot", "restore"],
        admin: ["health", "backup", "compaction", "metrics"],
        experimental: []
    )) {
        self.caps = caps
    }

    // MARK: - Corpus
    public func createCorpus(id: String, metadata: [String: String]) async throws {
        corpusMeta[id] = metadata
        docs[id] = docs[id] ?? [:]
    }

    public func getCorpus(id: String) async throws -> Corpus? {
        guard let meta = corpusMeta[id] else { return nil }
        return Corpus(id: id, metadata: meta)
    }

    public func deleteCorpus(id: String) async throws {
        corpusMeta.removeValue(forKey: id)
        docs.removeValue(forKey: id)
        snapshots.removeValue(forKey: id)
    }

    public func listCorpora(limit: Int, offset: Int) async throws -> (total: Int, corpora: [String]) {
        let ids = Array(corpusMeta.keys).sorted()
        let total = ids.count
        let slice = Array(ids.dropFirst(min(offset, total)).prefix(limit))
        return (total, slice)
    }

    // MARK: - Documents
    public func putDoc(corpusId: String, collection: String, id: String, body: Data) async throws {
        var corpus = docs[corpusId, default: [:]]
        var coll = corpus[collection, default: [:]]
        coll[id] = body
        corpus[collection] = coll
        docs[corpusId] = corpus
    }

    public func getDoc(corpusId: String, collection: String, id: String) async throws -> Data? {
        docs[corpusId]?[collection]?[id]
    }

    public func deleteDoc(corpusId: String, collection: String, id: String) async throws {
        docs[corpusId]?[collection]?[id] = nil
    }

    public func query(corpusId: String, collection: String, query: Query) async throws -> QueryResponse {
        let collDocs = docs[corpusId]?[collection] ?? [:]
        var result: [Data]

        if let mode = query.mode {
            switch mode {
            case .byId(let docId):
                if let d = collDocs[docId] {
                    return QueryResponse(total: 1, documents: [d])
                } else {
                    return QueryResponse(total: 0, documents: [])
                }
            case .byIndexEq(let field, let value):
                result = collDocs.values.filter { decode($0)[field] as? String == value }
            case .prefixScan(let field, let prefix):
                result = collDocs.values.filter { (decode($0)[field] as? String)?.hasPrefix(prefix) == true }
            }
        } else {
            result = Array(collDocs.values)
        }

        if !query.filters.isEmpty {
            result = result.filter { data in
                let obj = decode(data)
                for (k, v) in query.filters { if (obj[k] as? String) != v { return false } }
                return true
            }
        }

        if let first = query.sort.first {
            let field = first.field
            let asc = first.ascending
            result.sort { a, b in
                let av = decode(a)[field] as? String ?? ""
                let bv = decode(b)[field] as? String ?? ""
                return asc ? (av < bv) : (av > bv)
            }
        }

        let total = result.count
        let offset = min(query.offset ?? 0, total)
        let limit = query.limit ?? total
        let slice = Array(result.dropFirst(offset).prefix(limit))
        return QueryResponse(total: total, documents: slice)
    }

    private func decode(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: - Capabilities
    public func capabilities() async throws -> Capabilities { caps }

    // MARK: - Admin
    public func snapshot(corpusId: String) async throws {
        snapshots[corpusId] = docs[corpusId] ?? [:]
    }

    public func restore(corpusId: String) async throws {
        if let snap = snapshots[corpusId] {
            docs[corpusId] = snap
        }
    }

    public func backup(corpusId: String) async throws {}
    public func compaction(corpusId: String) async throws {}
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.

