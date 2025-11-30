import XCTest
@testable import SemanticBrowserService

private struct FakeBrowserEngine: BrowserEngine {
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

private final class RecordingBackend: SemanticMemoryService.Backend, @unchecked Sendable {
    var pages: [PageDoc] = []
    var segments: [SegmentDoc] = []
    var entities: [EntityDoc] = []
    var visuals: [SemanticMemoryService.VisualRecord] = []

    func upsert(page: PageDoc) { pages.append(page) }
    func upsert(segment: SegmentDoc) { segments.append(segment) }
    func upsert(entity: EntityDoc) { entities.append(entity) }
    func searchPages(q: String?, host: String?, lang: String?, limit: Int, offset: Int) -> (Int, [PageDoc]) { (pages.count, pages) }
    func searchSegments(q: String?, kind: String?, entity: String?, limit: Int, offset: Int) -> (Int, [SegmentDoc]) { (segments.count, segments) }
    func searchEntities(q: String?, type: String?, limit: Int, offset: Int) -> (Int, [EntityDoc]) { (entities.count, entities) }
    func upsertVisual(pageId: String, visual: SemanticMemoryService.VisualRecord) { visuals.append(visual) }
}

final class HandlersTests: XCTestCase {
    func testBrowseAndIndexPersistsToBackend() async throws {
        let backend = RecordingBackend()
        let service = SemanticMemoryService(backend: backend)
        let api = SemanticBrowserOpenAPI(service: service, engine: FakeBrowserEngine())

        let wait = Components.Schemas.WaitPolicy(strategy: .networkIdle, networkIdleMs: 0, selector: nil, maxWaitMs: 1000)
        let req = Components.Schemas.BrowseRequest(url: "https://example.com", wait: wait, mode: .standard, index: .init(enabled: true), storeArtifacts: false, labels: nil)
        let input = Operations.browseAndDissect.Input(body: .json(req))
        let output = try await api.browseAndDissect(input)
        guard case .ok(let ok) = output, case let .json(resp) = ok.body else {
            return XCTFail("expected ok json response")
        }
        XCTAssertEqual(resp.index?.pagesUpserted, 1)
        XCTAssertEqual(backend.pages.count, 1)
        XCTAssertFalse(backend.segments.isEmpty)
    }

    func testQueriesRequireBackend() async throws {
        let service = SemanticMemoryService(backend: nil)
        let api = SemanticBrowserOpenAPI(service: service, engine: FakeBrowserEngine())
        let qInput = Operations.queryPages.Input(query: .init(q: nil, host: nil, lang: nil, limit: 10, offset: 0))
        let res = try await api.queryPages(qInput)
        if case .undocumented(let status, _) = res {
            XCTAssertEqual(status, 503)
        } else {
            XCTFail("expected 503 when backend missing")
        }
    }
}
