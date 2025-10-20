import XCTest
import Foundation
import OpenAPIRuntime
@testable import SemanticBrowserService

final class VisualAnchorsTests: XCTestCase {
    func testAnalyzeYieldsSyntheticRectAnchors() async throws {
        let svc = SemanticMemoryService()
        let api = SemanticBrowserOpenAPI(service: svc, engine: URLFetchBrowserEngine())

        // Build inline snapshot payload
        let html = "<html><body><h1>Title</h1><p>First paragraph.</p><p>Second paragraph.</p></body></html>"
        let text = "Title First paragraph. Second paragraph."
        let snapshot = Components.Schemas.Snapshot(
            snapshotId: "snap-1",
            page: .init(uri: "https://example.com", finalUrl: "https://example.com", fetchedAt: Date(), status: 200, contentType: "text/html", navigation: .init(ttfbMs: nil, loadMs: 10)),
            rendered: .init(html: html, text: text, image: nil, meta: nil),
            network: nil,
            diagnostics: nil
        )
        let body = Operations.analyzeSnapshot.Input.Body.json(.init(snapshot: snapshot, snapshotRef: nil, mode: .standard))
        let out = try await api.analyzeSnapshot(.init(body: body))
        guard case .ok(let ok) = out else { return XCTFail("expected ok") }
        let analysis = try ok.body.json
        // Assert at least one block has rects
        XCTAssertTrue(analysis.blocks.contains(where: { ($0.rects?.isEmpty == false) }))
    }
}
