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
}

