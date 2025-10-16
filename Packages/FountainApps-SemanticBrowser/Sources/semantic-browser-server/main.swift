import Foundation
import LauncherSignature
import FountainRuntime
import SemanticBrowserService
import FountainStoreClient
import Dispatch

verifyLauncherSignature()

final class FountainStoreBackend: SemanticMemoryService.Backend, @unchecked Sendable {
    private final class ResultBox<Value>: @unchecked Sendable {
        var value: Value?
    }

    private let store: FountainStoreClient
    private let corpusId: String
    private let pagesCollection: String
    private let segmentsCollection: String
    private let entitiesCollection: String

    init(store: FountainStoreClient, corpusId: String, pagesCollection: String = "pages", segmentsCollection: String = "segments", entitiesCollection: String = "entities") {
        self.store = store
        self.corpusId = corpusId
        self.pagesCollection = pagesCollection
        self.segmentsCollection = segmentsCollection
        self.entitiesCollection = entitiesCollection

        Task {
            if (try? await store.getCorpus(corpusId)) == nil {
                _ = try? await store.createCorpus(corpusId, metadata: ["source": "semantic-browser"])
            }
        }
    }

    func upsert(page: PageDoc) {
        Task {
            guard let data = try? JSONEncoder().encode(page) else { return }
            try? await store.putDoc(corpusId: corpusId, collection: pagesCollection, id: page.id, body: data)
        }
    }

    func upsert(segment: SegmentDoc) {
        Task {
            guard let data = try? JSONEncoder().encode(segment) else { return }
            try? await store.putDoc(corpusId: corpusId, collection: segmentsCollection, id: segment.id, body: data)
        }
    }

    func upsert(entity: EntityDoc) {
        Task {
            guard let data = try? JSONEncoder().encode(entity) else { return }
            try? await store.putDoc(corpusId: corpusId, collection: entitiesCollection, id: entity.id, body: data)
        }
    }

    private func runSync<T>(_ work: @escaping @Sendable () async throws -> T) -> Result<T, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        let storage = ResultBox<Result<T, Error>>()
        Task.detached(priority: nil, operation: { @Sendable () async in
            let result: Result<T, Error>
            do {
                let value = try await work()
                result = .success(value)
            } catch {
                result = .failure(error)
            }
            storage.value = result
            semaphore.signal()
        })
        semaphore.wait()
        return storage.value!
    }

    func searchPages(q: String?, host: String?, lang: String?, limit: Int, offset: Int) -> (Int, [PageDoc]) {
        var filters: [String: String] = [:]
        if let host, !host.isEmpty { filters["host"] = host }
        if let lang, !lang.isEmpty { filters["lang"] = lang }
        let query = Query(filters: filters, text: q?.isEmpty == true ? nil : q, limit: limit, offset: offset)
        let result = runSync {
            try await self.store.query(corpusId: self.corpusId, collection: self.pagesCollection, query: query)
        }
        guard case .success(let response) = result else { return (0, []) }
        let decoder = JSONDecoder()
        let items = response.documents.compactMap { try? decoder.decode(PageDoc.self, from: $0) }
        return (response.total, items)
    }

    func searchSegments(q: String?, kind: String?, entity: String?, limit: Int, offset: Int) -> (Int, [SegmentDoc]) {
        var filters: [String: String] = [:]
        if let kind, !kind.isEmpty { filters["kind"] = kind }
        if let entity, !entity.isEmpty { filters["entities"] = entity }
        let query = Query(filters: filters, text: q?.isEmpty == true ? nil : q, limit: limit, offset: offset)
        let result = runSync {
            try await self.store.query(corpusId: self.corpusId, collection: self.segmentsCollection, query: query)
        }
        guard case .success(let response) = result else { return (0, []) }
        let decoder = JSONDecoder()
        let items = response.documents.compactMap { try? decoder.decode(SegmentDoc.self, from: $0) }
        return (response.total, items)
    }

    func searchEntities(q: String?, type: String?, limit: Int, offset: Int) -> (Int, [EntityDoc]) {
        var filters: [String: String] = [:]
        if let type, !type.isEmpty { filters["type"] = type }
        let query = Query(filters: filters, text: q?.isEmpty == true ? nil : q, limit: limit, offset: offset)
        let result = runSync {
            try await self.store.query(corpusId: self.corpusId, collection: self.entitiesCollection, query: query)
        }
        guard case .success(let response) = result else { return (0, []) }
        let decoder = JSONDecoder()
        let items = response.documents.compactMap { try? decoder.decode(EntityDoc.self, from: $0) }
        return (response.total, items)
    }
}

func buildService(backend: SemanticMemoryService.Backend? = nil) -> SemanticMemoryService {
    SemanticMemoryService(backend: backend)
}

func makeFountainStoreBackend(from env: [String: String]) -> SemanticMemoryService.Backend? {
    guard let path = env["SB_STORE_PATH"], !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
    }
    let resolved = path.hasPrefix("~") ? (FileManager.default.homeDirectoryForCurrentUser.path + path.dropFirst()) : path
    let url = URL(fileURLWithPath: resolved, isDirectory: true)
    do {
        let disk = try DiskFountainStoreClient(rootDirectory: url)
        let store = FountainStoreClient(client: disk)
        let corpus = env["SB_STORE_CORPUS"].flatMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } ?? "semantic-browser"
        let pagesCollection = env["SB_PAGES_COLLECTION"] ?? "pages"
        let segmentsCollection = env["SB_SEGMENTS_COLLECTION"] ?? "segments"
        let entitiesCollection = env["SB_ENTITIES_COLLECTION"] ?? "entities"
        return FountainStoreBackend(
            store: store,
            corpusId: corpus,
            pagesCollection: pagesCollection,
            segmentsCollection: segmentsCollection,
            entitiesCollection: entitiesCollection
        )
    } catch {
        print("semantic-browser: failed to configure FountainStore backend (\\(error))")
        return nil
    }
}

Task {
    let env = ProcessInfo.processInfo.environment
    let backend = makeFountainStoreBackend(from: env)
    let service = buildService(backend: backend)
    // Serve generated OpenAPI handlers via a lightweight NIO transport.
    let fallback = FountainRuntime.HTTPKernel { req in
        if req.method == "GET" && req.path == "/metrics" {
            return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: Data("ok\n".utf8))
        }
        if req.method == "GET" && req.path == "/openapi.yaml" {
            let url = URL(fileURLWithPath: "Packages/FountainServiceKit-SemanticBrowser/Sources/SemanticBrowserService/openapi.yaml")
            if let data = try? Data(contentsOf: url) {
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
            }
        }
        return HTTPResponse(status: 404)
    }
    // Choose engine based on environment
    let engine: BrowserEngine = {
        if let ws = env["SB_CDP_URL"], let u = URL(string: ws) { return CDPBrowserEngine(wsURL: u) }
        if let bin = env["SB_BROWSER_CLI"] {
            return ShellBrowserEngine(
                binary: bin,
                args: (env["SB_BROWSER_ARGS"] ?? "").split(separator: " ").map(String.init)
            )
        }
        return URLFetchBrowserEngine()
    }()
    let transport = NIOOpenAPIServerTransport(fallback: fallback)
    let api = SemanticBrowserOpenAPI(service: service, engine: engine)
    // Register generated handlers; use root prefix.
    try? api.registerHandlers(on: transport, serverURL: URL(string: "/")!)
    let server = NIOHTTPServer(kernel: transport.asKernel())
    let port = Int(env["SEMANTIC_BROWSER_PORT"] ?? env["PORT"] ?? "8007") ?? 8007
    _ = try? await server.start(port: port)
    if backend != nil {
        let corpus = env["SB_STORE_CORPUS"] ?? "semantic-browser"
        print("semantic-browser using FountainStore corpus \(corpus)")
    }
    print("semantic-browser listening on \(port)")
}
RunLoop.main.run()

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
