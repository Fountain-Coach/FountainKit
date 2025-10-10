import XCTest
@testable import FountainStoreClient

final class FountainStoreClientTextSearchTests: XCTestCase {
    func makeClient(withTextCapability: Bool) -> FountainStoreClient {
        let caps = Capabilities(
            corpus: true,
            documents: ["upsert", "get", "delete"],
            query: withTextCapability ? ["byId", "byIndexEq", "prefixScan", "filters", "sort", "text"] : ["byId", "byIndexEq", "prefixScan", "filters", "sort"],
            transactions: ["snapshot", "restore"],
            admin: ["health"],
            experimental: []
        )
        let embedded = EmbeddedFountainStoreClient(caps: caps)
        return FountainStoreClient(client: embedded)
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

    func testTextSearchPagesServerSide() async throws {
        let client = makeClient(withTextCapability: true)
        try await seedPages(client, corpusId: "c1")

        let q = Query(filters: ["corpusId": "c1"], sort: [("title", true)], text: "swift", limit: 50, offset: 0)
        let resp = try await client.query(corpusId: "c1", collection: "pages", query: q)
        XCTAssertEqual(resp.total, 1)
        let titles = try resp.documents.map { try JSONDecoder().decode(Page.self, from: $0).title }
        XCTAssertEqual(titles, ["Swift NIO Guide"])
    }

    func testTextSearchSegmentsServerSide() async throws {
        let client = makeClient(withTextCapability: true)
        _ = try await client.createCorpus("c2")
        let segs: [Segment] = [
            .init(corpusId: "c2", segmentId: "s1", pageId: "p1", kind: "text", text: "Hello World"),
            .init(corpusId: "c2", segmentId: "s2", pageId: "p1", kind: "code", text: "swift is fun"),
            .init(corpusId: "c2", segmentId: "s3", pageId: "p2", kind: "text", text: "Random note")
        ]
        for s in segs { _ = try await client.addSegment(s) }

        let q = Query(filters: ["corpusId": "c2"], text: "swift", limit: 50, offset: 0)
        let resp = try await client.query(corpusId: "c2", collection: "segments", query: q)
        XCTAssertEqual(resp.total, 1)
        let ids = try resp.documents.map { try JSONDecoder().decode(Segment.self, from: $0).segmentId }
        XCTAssertEqual(ids, ["s2"])
    }

    func testTextSearchSortAndPagination() async throws {
        let client = makeClient(withTextCapability: true)
        try await seedPages(client, corpusId: "c3")
        let q = Query(filters: ["corpusId": "c3"], sort: [("title", true)], text: "a", limit: 1, offset: 1)
        let resp = try await client.query(corpusId: "c3", collection: "pages", query: q)
        XCTAssertGreaterThanOrEqual(resp.total, 2)
        XCTAssertEqual(resp.documents.count, 1)
        let page = try JSONDecoder().decode(Page.self, from: resp.documents[0])
        // Titles with 'a' sorted ascending: Another Article, OpenAPI Tools.
        // Offset 1 should pick the second one.
        XCTAssertEqual(page.title, "OpenAPI Tools")
    }

    func testTextCapabilityMissing() async throws {
        let client = makeClient(withTextCapability: false)
        try await seedPages(client, corpusId: "c4")
        do {
            let q = Query(filters: ["corpusId": "c4"], text: "swift")
            _ = try await client.query(corpusId: "c4", collection: "pages", query: q)
            XCTFail("Expected notSupported error for query.text capability")
        } catch PersistenceError.notSupported(let need) {
            XCTAssertEqual(need, "query.text")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

