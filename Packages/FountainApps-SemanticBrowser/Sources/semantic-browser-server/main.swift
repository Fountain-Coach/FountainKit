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
    private let visualsCollection: String

    init(store: FountainStoreClient, corpusId: String, pagesCollection: String = "pages", segmentsCollection: String = "segments", entitiesCollection: String = "entities", visualsCollection: String = "visuals") {
        self.store = store
        self.corpusId = corpusId
        self.pagesCollection = pagesCollection
        self.segmentsCollection = segmentsCollection
        self.entitiesCollection = entitiesCollection
        self.visualsCollection = visualsCollection

        Task {
            if (try? await store.getCorpus(corpusId)) == nil {
                _ = try? await store.createCorpus(corpusId, metadata: ["source": "semantic-browser"])
            }
        }
    }

    func upsert(page: PageDoc) {
        // Persist using FountainStoreClient models so documents include corpusId.
        Task {
            let mapped = Page(
                corpusId: corpusId,
                pageId: page.id,
                url: page.url,
                host: page.host,
                title: page.title ?? page.url
            )
            guard let data = try? JSONEncoder().encode(mapped) else { return }
            try? await store.putDoc(corpusId: corpusId, collection: pagesCollection, id: mapped.pageId, body: data)
        }
    }

    func upsert(segment: SegmentDoc) {
        // Persist using FountainStoreClient models so documents include corpusId.
        Task {
            let mapped = Segment(
                corpusId: corpusId,
                segmentId: segment.id,
                pageId: segment.pageId,
                kind: segment.kind,
                text: segment.text
            )
            guard let data = try? JSONEncoder().encode(mapped) else { return }
            try? await store.putDoc(corpusId: corpusId, collection: segmentsCollection, id: mapped.segmentId, body: data)
        }
    }

    func upsert(entity: EntityDoc) {
        // Persist using FountainStoreClient models so documents include corpusId.
        Task {
            let mapped = Entity(
                corpusId: corpusId,
                entityId: entity.id,
                name: entity.name,
                type: entity.type
            )
            guard let data = try? JSONEncoder().encode(mapped) else { return }
            try? await store.putDoc(corpusId: corpusId, collection: entitiesCollection, id: mapped.entityId, body: data)
        }
    }

    private func runSync<T>(_ work: @escaping @Sendable () async throws -> T) -> Result<T, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        let storage = ResultBox<Result<T, Error>>()
        Task(priority: nil) { @Sendable in
            let result: Result<T, Error>
            do {
                let value = try await work()
                result = .success(value)
            } catch {
                result = .failure(error)
            }
            storage.value = result
            semaphore.signal()
        }
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
        let items: [PageDoc] = response.documents.compactMap { (data: Data) -> PageDoc? in
            if let doc = try? decoder.decode(PageDoc.self, from: data) {
                return doc
            }
            if let p = try? decoder.decode(Page.self, from: data) {
                return PageDoc(id: p.pageId, url: p.url, host: p.host, status: nil, contentType: nil, lang: nil, title: p.title, textSize: nil, fetchedAt: nil, labels: nil)
            }
            return nil
        }
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
        let items: [SegmentDoc] = response.documents.compactMap { (data: Data) -> SegmentDoc? in
            if let s = try? decoder.decode(SegmentDoc.self, from: data) { return s }
            if let s = try? decoder.decode(Segment.self, from: data) {
                return SegmentDoc(id: s.segmentId, pageId: s.pageId, kind: s.kind, text: s.text)
            }
            return nil
        }
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
        let items: [EntityDoc] = response.documents.compactMap { (data: Data) -> EntityDoc? in
            if let e = try? decoder.decode(EntityDoc.self, from: data) { return e }
            if let e = try? decoder.decode(Entity.self, from: data) {
                return EntityDoc(id: e.entityId, name: e.name, type: e.type)
            }
            return nil
        }
        return (response.total, items)
    }

    struct VisualDoc: Codable { let pageId: String; let image: Image?; let anchors: [Anchor]; let coveragePercent: Float?; struct Image: Codable { let imageId: String; let contentType: String; let width: Int; let height: Int; let scale: Float; let fetchedAt: Double? }; struct Anchor: Codable { let imageId: String; let x: Float; let y: Float; let w: Float; let h: Float; let excerpt: String?; let confidence: Float?; let ts: Double? } }
    func upsertVisual(pageId: String, visual: SemanticMemoryService.VisualRecord) {
        Task {
            let image = visual.asset.map { VisualDoc.Image(imageId: $0.imageId, contentType: $0.contentType, width: $0.width, height: $0.height, scale: $0.scale, fetchedAt: $0.fetchedAt?.timeIntervalSince1970) }
            let anchors = visual.anchors.map { VisualDoc.Anchor(imageId: $0.imageId, x: $0.x, y: $0.y, w: $0.w, h: $0.h, excerpt: $0.excerpt, confidence: $0.confidence, ts: $0.ts?.timeIntervalSince1970) }
            let doc = VisualDoc(pageId: pageId, image: image, anchors: anchors, coveragePercent: visual.coveragePercent)
            guard let data = try? JSONEncoder().encode(doc) else { return }
            try? await store.putDoc(corpusId: corpusId, collection: visualsCollection, id: pageId, body: data)
        }
    }
}

func buildService(backend: SemanticMemoryService.Backend? = nil) -> SemanticMemoryService {
    SemanticMemoryService(backend: backend)
}

func makeFountainStoreBackend(from env: [String: String]) -> SemanticMemoryService.Backend? {
    // Prefer explicit path, fall back to shared FountainStore root in the workspace.
    let rawPath = env["SB_STORE_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        ?? env["FOUNTAINSTORE_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        ?? ".fountain/store"
    guard !rawPath.isEmpty else { return nil }
    let resolved = rawPath.hasPrefix("~") ? (FileManager.default.homeDirectoryForCurrentUser.path + rawPath.dropFirst()) : rawPath
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
            entitiesCollection: entitiesCollection,
            visualsCollection: env["SB_VISUALS_COLLECTION"] ?? "visuals"
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
        if req.method == "GET" && req.path.hasPrefix("/assets/") {
            let parts = req.path.split(separator: "/").map(String.init)
            if parts.count == 3, let imageName = parts.last, imageName.hasSuffix(".png") {
                let imageId = String(imageName.dropLast(4))
                if let ref = await service.loadArtifactRef(ownerId: imageId, kind: "image/png"), let data = try? Data(contentsOf: URL(fileURLWithPath: ref)) {
                    return HTTPResponse(status: 200, headers: ["Content-Type": "image/png", "Content-Length": "\(data.count)", "Cache-Control": "no-cache"], body: data)
                }
                return HTTPResponse(status: 404, headers: ["Content-Type": "application/json"], body: Data("{\"error\":\"not found\"}".utf8))
            }
            return HTTPResponse(status: 400, headers: ["Content-Type": "application/json"], body: Data("{\"error\":\"invalid asset path\"}".utf8))
        }
        return HTTPResponse(status: 404)
    }
    // Choose engine based on environment. Default now REQUIRES a CDP WebSocket URL.
    // To allow the simplified URLSession fetcher for testing, set SB_ALLOW_URLFETCH=1 explicitly.
    let engine: BrowserEngine = {
        if let ws = env["SB_CDP_URL"], let u = URL(string: ws), !ws.isEmpty {
            print("semantic-browser using engine=cdp url=\(ws)")
            return CDPBrowserEngine(wsURL: u)
        }
        if let bin = env["SB_BROWSER_CLI"], !bin.isEmpty {
            print("semantic-browser using engine=shell bin=\(bin)")
            return ShellBrowserEngine(
                binary: bin,
                args: (env["SB_BROWSER_ARGS"] ?? "").split(separator: " ").map(String.init)
            )
        }
        if env["SB_ALLOW_URLFETCH"] == "1" {
            print("semantic-browser WARNING: falling back to engine=urlfetch (no JS). Set SB_CDP_URL to use headless Chrome.")
            return URLFetchBrowserEngine()
        }
        // Hard fail: no proper engine configured
        FileHandle.standardError.write(Data("semantic-browser ERROR: No CDP engine configured. Set SB_CDP_URL or SB_BROWSER_CLI.\n".utf8))
        exit(2)
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
