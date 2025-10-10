import XCTest
import FountainStoreClient
@testable import PersistService

final class PersistServiceHandlersSearchTests: XCTestCase {
    func makeAPI(withTextCapability: Bool) -> (api: PersistOpenAPI, client: FountainStoreClient) {
        let caps = Capabilities(
            corpus: true,
            documents: ["upsert", "get", "delete"],
            query: withTextCapability ? ["byId", "byIndexEq", "prefixScan", "filters", "sort", "text"] : ["byId", "byIndexEq", "prefixScan", "filters", "sort"],
            transactions: ["snapshot", "restore"],
            admin: ["health"],
            experimental: []
        )
        let embedded = EmbeddedFountainStoreClient(caps: caps)
        let client = FountainStoreClient(client: embedded)
        return (PersistOpenAPI(persistence: client), client)
    }

    func seedPages(_ client: FountainStoreClient, corpusId: String) async throws {
        _ = try await client.createCorpus(corpusId)
        let pages: [Page] = [
            .init(corpusId: corpusId, pageId: "p1", url: "https://swift.org/NIO", host: "swift.org", title: "Swift NIO Guide"),
            .init(corpusId: corpusId, pageId: "p2", url: "https://dev.local/openapi", host: "dev.local", title: "OpenAPI Tools"),
            .init(corpusId: corpusId, pageId: "p3", url: "https://example.com/blog", host: "example.com", title: "Another Article")
        ]
        for p in pages { _ = try await client.addPage(p) }
    }

    func seedSegments(_ client: FountainStoreClient, corpusId: String) async throws {
        _ = try await client.createCorpus(corpusId)
        let segs: [Segment] = [
            .init(corpusId: corpusId, segmentId: "s1", pageId: "p1", kind: "text", text: "Hello World"),
            .init(corpusId: corpusId, segmentId: "s2", pageId: "p1", kind: "code", text: "swift is fun"),
            .init(corpusId: corpusId, segmentId: "s3", pageId: "p2", kind: "text", text: "Random note")
        ]
        for s in segs { _ = try await client.addSegment(s) }
    }

    func testListPagesServerSideTextSearch() async throws {
        let (api, client) = makeAPI(withTextCapability: true)
        try await seedPages(client, corpusId: "cps1")
        let input = Operations.listPages.Input(
            path: .init(corpusId: "cps1"),
            query: .init(host: nil, q: "swift", limit: 50, offset: 0, sort: "title"),
            headers: .init()
        )
        let out = try await api.listPages(input)
        guard case let .ok(ok) = out, case let .json(body) = ok.body else {
            return XCTFail("expected 200 json response")
        }
        XCTAssertEqual(body.total, 1)
        XCTAssertEqual(body.pages?.first?.value2.title, "Swift NIO Guide")
    }

    func testListSegmentsFallbackTextSearch() async throws {
        let (api, client) = makeAPI(withTextCapability: false)
        try await seedSegments(client, corpusId: "cps2")
        let input = Operations.listSegments.Input(
            path: .init(corpusId: "cps2"),
            query: .init(kind: nil, q: "swift", limit: 50, offset: 0, sort: "segmentId"),
            headers: .init()
        )
        let out = try await api.listSegments(input)
        guard case let .ok(ok) = out, case let .json(body) = ok.body else {
            return XCTFail("expected 200 json response")
        }
        XCTAssertEqual(body.total, 1)
        XCTAssertEqual(body.segments?.first?.value2.segmentId, "s2")
    }

    func testListEntitiesServerSideTextSearch() async throws {
        let (api, client) = makeAPI(withTextCapability: true)
        _ = try await client.createCorpus("cps3")
        let entities: [Entity] = [
            .init(corpusId: "cps3", entityId: "e1", name: "Swift", type: "lang"),
            .init(corpusId: "cps3", entityId: "e2", name: "OpenAPI", type: "spec"),
            .init(corpusId: "cps3", entityId: "e3", name: "NIO", type: "lib")
        ]
        for e in entities { _ = try await client.addEntity(e) }

        let input = Operations.listEntities.Input(
            path: .init(corpusId: "cps3"),
            query: .init(_type: nil, q: "api", limit: 50, offset: 0, sort: "name"),
            headers: .init()
        )
        let out = try await api.listEntities(input)
        guard case let .ok(ok) = out, case let .json(body) = ok.body else {
            return XCTFail("expected 200 json response")
        }
        XCTAssertEqual(body.total, 1)
        XCTAssertEqual(body.entities?.first?.value2.name, "OpenAPI")
    }

    func testPagesSortAndPaginationDescending() async throws {
        let (api, client) = makeAPI(withTextCapability: true)
        try await seedPages(client, corpusId: "cps4")
        // Use q to ensure search path; sort by host descending; paginate to first item
        let input = Operations.listPages.Input(
            path: .init(corpusId: "cps4"),
            query: .init(host: nil, q: "https://", limit: 1, offset: 0, sort: "-host"),
            headers: .init()
        )
        let out = try await api.listPages(input)
        guard case let .ok(ok) = out, case let .json(body) = ok.body, let page = body.pages?.first else {
            return XCTFail("expected 200 json response")
        }
        // Hosts present: swift.org, dev.local, example.com -> descending starts with swift.org
        XCTAssertEqual(page.value2.host, "swift.org")
    }

    func testPagesInvalidSortKeyGraceful() async throws {
        let (api, client) = makeAPI(withTextCapability: false) // force fallback path for visibility
        try await seedPages(client, corpusId: "cps5")
        let input = Operations.listPages.Input(
            path: .init(corpusId: "cps5"),
            query: .init(host: nil, q: "a", limit: 10, offset: 0, sort: "doesNotExist"),
            headers: .init()
        )
        let out = try await api.listPages(input)
        guard case let .ok(ok) = out, case let .json(body) = ok.body else {
            return XCTFail("expected 200 json response")
        }
        XCTAssertNotNil(body.pages)
        XCTAssertGreaterThan((body.pages ?? []).count, 0)
    }
}
