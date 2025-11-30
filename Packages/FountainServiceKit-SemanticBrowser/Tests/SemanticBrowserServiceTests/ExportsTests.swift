import XCTest
@testable import SemanticBrowserService

private struct TestBrowserEngine: BrowserEngine {
    func snapshotHTML(for url: String) async throws -> (html: String, text: String) {
        return ("<html><body><h1>Title</h1><p>Body</p></body></html>", "Title Body")
    }

    func snapshot(for url: String, wait: APIModels.WaitPolicy?, capture: CaptureOptions?) async throws -> SnapshotResult {
        return SnapshotResult(
            html: "<html><body><h1>Title</h1><p>Body</p></body></html>",
            text: "Title Body",
            finalURL: url,
            loadMs: 10,
            network: nil,
            pageStatus: 200,
            pageContentType: "text/html",
            adminNetwork: nil,
            screenshotPNG: nil,
            screenshotWidth: nil,
            screenshotHeight: nil,
            screenshotScale: nil,
            blockRects: nil
        )
    }
}

private final class TestBackend: SemanticMemoryService.Backend, @unchecked Sendable {
    var pages: [PageDoc] = []
    var segments: [SegmentDoc] = []
    var entities: [EntityDoc] = []
    func upsert(page: PageDoc) { pages.append(page) }
    func upsert(segment: SegmentDoc) { segments.append(segment) }
    func upsert(entity: EntityDoc) { entities.append(entity) }
    func searchPages(q: String?, host: String?, lang: String?, limit: Int, offset: Int) -> (Int, [PageDoc]) { (pages.count, pages) }
    func searchSegments(q: String?, kind: String?, entity: String?, limit: Int, offset: Int) -> (Int, [SegmentDoc]) { (segments.count, segments) }
    func searchEntities(q: String?, type: String?, limit: Int, offset: Int) -> (Int, [EntityDoc]) { (entities.count, entities) }
    func upsertVisual(pageId: String, visual: SemanticMemoryService.VisualRecord) {}
}

final class ExportsTests: XCTestCase {
    func testExportRequiresBackend() async throws {
        let service = SemanticMemoryService(backend: nil)
        let api = SemanticBrowserOpenAPI(service: service, engine: TestBrowserEngine())
        let input = Operations.exportArtifacts.Input(query: .init(pageId: "p1", format: .snapshot_period_html))
        let res = try await api.exportArtifacts(input)
        if case .undocumented(let status, _) = res {
            XCTAssertEqual(status, 503)
        } else {
            XCTFail("expected 503 when backend missing")
        }
    }

    func testExportSnapshotWhenPresent() async throws {
        let backend = TestBackend()
        let service = SemanticMemoryService(backend: backend)
        let api = SemanticBrowserOpenAPI(service: service, engine: TestBrowserEngine())
        // Seed a snapshot by ingesting through browse
        let wait = Components.Schemas.WaitPolicy(strategy: .networkIdle, networkIdleMs: 0, selector: nil, maxWaitMs: 1000)
        let req = Components.Schemas.BrowseRequest(url: "https://example.com", wait: wait, mode: .standard, index: .init(enabled: true), storeArtifacts: false, labels: nil)
        let resp = try await api.browseAndDissect(Operations.browseAndDissect.Input(body: .json(req)))
        guard case .ok(let ok) = resp, case let .json(body) = ok.body else { return XCTFail("expected browse response") }
        let snapId = body.snapshot.snapshotId
        let input = Operations.exportArtifacts.Input(query: .init(pageId: snapId, format: .snapshot_period_text))
        let res = try await api.exportArtifacts(input)
        if case .ok(let ok) = res, case let .plainText(body) = ok.body {
            var collected = Data()
            for try await chunk in body {
                collected.append(contentsOf: chunk)
                if collected.count > 0 { break }
            }
            XCTAssertFalse(collected.isEmpty)
        } else {
            XCTFail("expected export body")
        }
    }
}
