import Foundation

public enum PersistenceError: Error, Equatable {
    case invalidData
    case notSupported(need: String)
}

public actor FountainStoreClient {
    private let client: FountainStoreClientProtocol
    private var caps: Capabilities?
    private var capabilityCounters: [String: Int] = [:]

    public init(client: FountainStoreClientProtocol) {
        self.client = client
        Task { try? await self.loadCapabilities() }
    }

    public var capabilityRequests: [String: Int] { capabilityCounters }

    private func loadCapabilities() async throws -> Capabilities {
        if let c = caps { return c }
        let fetched = try await client.capabilities()
        caps = fetched
        return fetched
    }

    private func hasCapability(_ c: Capabilities, need: String) -> Bool {
        let parts = need.split(separator: ".")
        if parts.count == 1 { return parts[0] == "corpus" ? c.corpus : false }
        guard parts.count == 2 else { return false }
        let group = parts[0], op = parts[1]
        switch group {
        case "documents": return c.documents.contains(String(op))
        case "query": return c.query.contains(String(op))
        case "transactions": return c.transactions.contains(String(op))
        case "admin": return c.admin.contains(String(op))
        case "experimental": return c.experimental.contains(String(op))
        default: return false
        }
    }

    private func requireCapability(_ need: String) async throws {
        let c = try await loadCapabilities()
        if hasCapability(c, need: need) { return }
        capabilityCounters[need, default: 0] += 1
        print("capability request: need=\(need)")
        throw PersistenceError.notSupported(need: need)
    }

    // MARK: - Corpus
    public func createCorpus(_ id: String, metadata: [String: String] = [:]) async throws -> CorpusResponse {
        try await requireCapability("corpus")
        try await client.createCorpus(id: id, metadata: metadata)
        return CorpusResponse(corpusId: id, message: "created")
    }

    public func createCorpus(_ req: CorpusCreateRequest) async throws -> CorpusResponse {
        try await createCorpus(req.corpusId)
    }

    public func getCorpus(_ id: String) async throws -> Corpus? {
        try await requireCapability("corpus")
        return try await client.getCorpus(id: id)
    }

    public func deleteCorpus(_ id: String) async throws {
        try await requireCapability("corpus")
        try await client.deleteCorpus(id: id)
    }

    public func listCorpora(limit: Int = 50, offset: Int = 0) async throws -> (total: Int, corpora: [String]) {
        try await requireCapability("corpus")
        return try await client.listCorpora(limit: limit, offset: offset)
    }

    // MARK: - Documents
    public func putDoc(corpusId: String, collection: String, id: String, body: Data) async throws {
        try await requireCapability("documents.upsert")
        try await client.putDoc(corpusId: corpusId, collection: collection, id: id, body: body)
    }

    public func getDoc(corpusId: String, collection: String, id: String) async throws -> Data? {
        try await requireCapability("documents.get")
        return try await client.getDoc(corpusId: corpusId, collection: collection, id: id)
    }

    public func deleteDoc(corpusId: String, collection: String, id: String) async throws {
        try await requireCapability("documents.delete")
        try await client.deleteDoc(corpusId: corpusId, collection: collection, id: id)
    }

    public func query(corpusId: String, collection: String, query: Query) async throws -> QueryResponse {
        try validateQuery(query)
        if let mode = query.mode {
            switch mode {
            case .byId: try await requireCapability("query.byId")
            case .byIndexEq: try await requireCapability("query.byIndexEq")
            case .prefixScan: try await requireCapability("query.prefixScan")
            }
        }
        if !query.filters.isEmpty { try await requireCapability("query.filters") }
        if !query.sort.isEmpty { try await requireCapability("query.sort") }
        if let text = query.text, !text.isEmpty { try await requireCapability("query.text") }
        return try await client.query(corpusId: corpusId, collection: collection, query: query)
    }

    private func validateQuery(_ q: Query) throws {
        if q.sort.count > 1 {
            try requestCapability("query.sort.multi")
        }
        if let mode = q.mode {
            switch mode {
            case .byId:
                if !q.filters.isEmpty || !q.sort.isEmpty || q.text != nil || q.limit != nil || q.offset != nil {
                    try requestCapability("query.byId.invalid")
                }
            case .byIndexEq, .prefixScan:
                if !q.filters.isEmpty || q.text != nil {
                    try requestCapability("query.modeWithFilters")
                }
            }
        }
    }

    private func requestCapability(_ need: String) throws -> Never {
        capabilityCounters[need, default: 0] += 1
        print("capability request: need=\(need)")
        throw PersistenceError.notSupported(need: need)
    }

    // MARK: - Capabilities
    public func capabilities() async throws -> Capabilities { try await loadCapabilities() }

    // MARK: - Admin
    public func snapshot(corpusId: String) async throws {
        try await requireCapability("transactions.snapshot")
        try await client.snapshot(corpusId: corpusId)
    }

    public func restore(corpusId: String) async throws {
        try await requireCapability("transactions.restore")
        try await client.restore(corpusId: corpusId)
    }

    public func backup(corpusId: String) async throws {
        try await requireCapability("admin.backup")
        try await client.backup(corpusId: corpusId)
    }

    public func compaction(corpusId: String) async throws {
        try await requireCapability("admin.compaction")
        try await client.compaction(corpusId: corpusId)
    }

    // MARK: - Convenience Helpers
    public func addPage(_ page: Page) async throws -> SuccessResponse {
        let payload = try JSONEncoder().encode(page)
        try await putDoc(corpusId: page.corpusId, collection: "pages", id: page.pageId, body: payload)
        return SuccessResponse(message: "ok")
    }

    public func listPages(corpusId: String, limit: Int = 50, offset: Int = 0) async throws -> (total: Int, pages: [Page]) {
        let q = Query(filters: ["corpusId": corpusId], limit: limit, offset: offset)
        let resp = try await query(corpusId: corpusId, collection: "pages", query: q)
        let list = try resp.documents.map { try JSONDecoder().decode(Page.self, from: $0) }
        return (resp.total, list)
    }

    public func addSegment(_ segment: Segment) async throws -> SuccessResponse {
        let payload = try JSONEncoder().encode(segment)
        try await putDoc(corpusId: segment.corpusId, collection: "segments", id: segment.segmentId, body: payload)
        return SuccessResponse(message: "ok")
    }

    public func listSegments(corpusId: String, limit: Int = 50, offset: Int = 0) async throws -> (total: Int, segments: [Segment]) {
        let q = Query(filters: ["corpusId": corpusId], limit: limit, offset: offset)
        let resp = try await query(corpusId: corpusId, collection: "segments", query: q)
        let list = try resp.documents.map { try JSONDecoder().decode(Segment.self, from: $0) }
        return (resp.total, list)
    }

    public func addEntity(_ entity: Entity) async throws -> SuccessResponse {
        let payload = try JSONEncoder().encode(entity)
        try await putDoc(corpusId: entity.corpusId, collection: "entities", id: entity.entityId, body: payload)
        return SuccessResponse(message: "ok")
    }

    public func listEntities(corpusId: String, limit: Int = 50, offset: Int = 0) async throws -> (total: Int, entities: [Entity]) {
        let q = Query(filters: ["corpusId": corpusId], limit: limit, offset: offset)
        let resp = try await query(corpusId: corpusId, collection: "entities", query: q)
        let list = try resp.documents.map { try JSONDecoder().decode(Entity.self, from: $0) }
        return (resp.total, list)
    }

    public func addTable(_ table: Table) async throws -> SuccessResponse {
        let payload = try JSONEncoder().encode(table)
        try await putDoc(corpusId: table.corpusId, collection: "tables", id: table.tableId, body: payload)
        return SuccessResponse(message: "ok")
    }

    public func listTables(corpusId: String, limit: Int = 50, offset: Int = 0) async throws -> (total: Int, tables: [Table]) {
        let q = Query(filters: ["corpusId": corpusId], limit: limit, offset: offset)
        let resp = try await query(corpusId: corpusId, collection: "tables", query: q)
        let list = try resp.documents.map { try JSONDecoder().decode(Table.self, from: $0) }
        return (resp.total, list)
    }

    public func addAnalysis(_ analysis: AnalysisRecord) async throws -> SuccessResponse {
        let payload = try JSONEncoder().encode(analysis)
        try await putDoc(corpusId: analysis.corpusId, collection: "analyses", id: analysis.analysisId, body: payload)
        return SuccessResponse(message: "ok")
    }

    public func listAnalyses(corpusId: String, limit: Int = 50, offset: Int = 0) async throws -> (total: Int, analyses: [AnalysisRecord]) {
        let q = Query(filters: ["corpusId": corpusId], limit: limit, offset: offset)
        let resp = try await query(corpusId: corpusId, collection: "analyses", query: q)
        let list = try resp.documents.map { try JSONDecoder().decode(AnalysisRecord.self, from: $0) }
        return (resp.total, list)
    }

    public func addBaseline(_ baseline: Baseline) async throws -> SuccessResponse {
        let payload = try JSONEncoder().encode(baseline)
        try await putDoc(corpusId: baseline.corpusId, collection: "baselines", id: baseline.baselineId, body: payload)
        return SuccessResponse(message: "ok")
    }

    public func listBaselines(corpusId: String, limit: Int = 50, offset: Int = 0) async throws -> (total: Int, baselines: [Baseline]) {
        let q = Query(filters: ["corpusId": corpusId], limit: limit, offset: offset)
        let resp = try await query(corpusId: corpusId, collection: "baselines", query: q)
        let list = try resp.documents.map { try JSONDecoder().decode(Baseline.self, from: $0) }
        return (resp.total, list)
    }

    public func addReflection(_ reflection: Reflection) async throws -> SuccessResponse {
        let payload = try JSONEncoder().encode(reflection)
        try await putDoc(corpusId: reflection.corpusId, collection: "reflections", id: reflection.reflectionId, body: payload)
        return SuccessResponse(message: "ok")
    }

    public func listReflections(corpusId: String, limit: Int = 50, offset: Int = 0) async throws -> (total: Int, reflections: [Reflection]) {
        let q = Query(filters: ["corpusId": corpusId], limit: limit, offset: offset)
        let resp = try await query(corpusId: corpusId, collection: "reflections", query: q)
        let list = try resp.documents.map { try JSONDecoder().decode(Reflection.self, from: $0) }
        return (resp.total, list)
    }

    public func addDrift(_ drift: Drift) async throws -> SuccessResponse {
        let payload = try JSONEncoder().encode(drift)
        try await putDoc(corpusId: drift.corpusId, collection: "drifts", id: drift.driftId, body: payload)
        return SuccessResponse(message: "ok")
    }

    public func listDrifts(corpusId: String, limit: Int = 50, offset: Int = 0) async throws -> (total: Int, drifts: [Drift]) {
        let q = Query(filters: ["corpusId": corpusId], limit: limit, offset: offset)
        let resp = try await query(corpusId: corpusId, collection: "drifts", query: q)
        let list = try resp.documents.map { try JSONDecoder().decode(Drift.self, from: $0) }
        return (resp.total, list)
    }

    public func addPatterns(_ patterns: Patterns) async throws -> SuccessResponse {
        let payload = try JSONEncoder().encode(patterns)
        try await putDoc(corpusId: patterns.corpusId, collection: "patterns", id: patterns.patternsId, body: payload)
        return SuccessResponse(message: "ok")
    }

    public func listPatterns(corpusId: String, limit: Int = 50, offset: Int = 0) async throws -> (total: Int, patterns: [Patterns]) {
        let q = Query(filters: ["corpusId": corpusId], limit: limit, offset: offset)
        let resp = try await query(corpusId: corpusId, collection: "patterns", query: q)
        let list = try resp.documents.map { try JSONDecoder().decode(Patterns.self, from: $0) }
        return (resp.total, list)
    }

    public func addRole(_ role: Role) async throws -> SuccessResponse {
        let payload = try JSONEncoder().encode(role)
        try await putDoc(corpusId: role.corpusId, collection: "roles", id: role.name, body: payload)
        return SuccessResponse(message: "ok")
    }

    public func seedDefaultRoles(corpusId: String, defaults: [Role]) async throws -> SuccessResponse {
        for role in defaults { _ = try await addRole(role) }
        return SuccessResponse(message: "seeded")
    }

    public func addFunction(_ function: FunctionModel) async throws -> SuccessResponse {
        let payload = try JSONEncoder().encode(function)
        try await putDoc(corpusId: function.corpusId, collection: "functions", id: function.functionId, body: payload)
        return SuccessResponse(message: "ok")
    }

    public func listFunctions(limit: Int = 50, offset: Int = 0, q: String? = nil) async throws -> (total: Int, functions: [FunctionModel]) {
        // gather functions from all corpora
        let (_, corpora) = try await listCorpora(limit: Int.max, offset: 0)
        var all: [FunctionModel] = []
        for corpus in corpora {
            let resp = try await query(corpusId: corpus, collection: "functions", query: Query())
            let list = try resp.documents.map { try JSONDecoder().decode(FunctionModel.self, from: $0) }
            all.append(contentsOf: list)
        }
        var list = all
        if let q = q, !q.isEmpty, q != "*" {
            let needle = q.lowercased()
            list = list.filter { fn in
                [fn.name, fn.description, fn.httpPath, fn.functionId, fn.corpusId]
                    .contains { $0.lowercased().contains(needle) }
            }
        }
        let total = list.count
        let slice = Array(list.dropFirst(min(offset, total)).prefix(limit))
        return (total, slice)
    }

    public func getFunctionDetails(functionId: String) async throws -> FunctionModel? {
        let (_, corpora) = try await listCorpora(limit: Int.max, offset: 0)
        for corpus in corpora {
            let resp = try await query(corpusId: corpus, collection: "functions", query: Query(mode: .byId(functionId)))
            if let doc = resp.documents.first {
                return try? JSONDecoder().decode(FunctionModel.self, from: doc)
            }
        }
        return nil
    }

    public func listFunctions(corpusId: String, limit: Int = 50, offset: Int = 0, q: String? = nil) async throws -> (total: Int, functions: [FunctionModel]) {
        let qobj = Query(filters: ["corpusId": corpusId])
        let resp = try await query(corpusId: corpusId, collection: "functions", query: qobj)
        var list = try resp.documents.map { try JSONDecoder().decode(FunctionModel.self, from: $0) }
        if let q = q, !q.isEmpty, q != "*" {
            let needle = q.lowercased()
            list = list.filter { fn in
                [fn.name, fn.description, fn.httpPath, fn.functionId, fn.corpusId]
                    .contains { $0.lowercased().contains(needle) }
            }
        }
        let total = list.count
        let slice = Array(list.dropFirst(min(offset, total)).prefix(limit))
        return (total, slice)
    }
}

public extension FountainStoreClient {
    /// Resolve and ensure required collections for the given corpus.
    /// Current implementation is a no-op placeholder until FountainStore
    /// exposes a management API for collection creation.
    func ensureCollections(corpusId: String = ProcessInfo.processInfo.environment["DEFAULT_CORPUS_ID"] ?? "tools-factory") async {
        _ = corpusId
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
