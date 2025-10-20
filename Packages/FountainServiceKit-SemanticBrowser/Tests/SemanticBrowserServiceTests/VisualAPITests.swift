import XCTest
@testable import SemanticBrowserService

final class VisualAPITests: XCTestCase {
    func testGetVisualReturnsPersistedAnchors() async throws {
        let svc = SemanticMemoryService()
        // Seed a visual record
        let asset = SemanticMemoryService.VisualAsset(imageId: "img-test", contentType: "image/png", width: 800, height: 600, scale: 1.0)
        let a = SemanticMemoryService.VisualAnchor(imageId: "img-test", x: 0.1, y: 0.2, w: 0.3, h: 0.4, excerpt: "hello", confidence: 0.9)
        await svc.storeVisual(pageId: "page-1", asset: asset, anchors: [a])

        // Serve via NIOHTTPServerCompat kernel
        let server = NIOHTTPServer(kernel: makeSemanticKernel(service: svc, engine: URLFetchBrowserEngine()))
        let port = try await server.start(port: 0)

        // GET /v1/visual?pageId=page-1
        var comps = URLComponents(string: "http://127.0.0.1:\(port)/v1/visual")!
        comps.queryItems = [URLQueryItem(name: "pageId", value: "page-1")]
        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let image = obj?["image"] as? [String: Any]
        XCTAssertEqual(image?["imageId"] as? String, "img-test")
        let anchors = obj?["anchors"] as? [[String: Any]]
        XCTAssertEqual(anchors?.count, 1)
        if let r = anchors?.first {
            XCTAssertEqual(r["imageId"] as? String, "img-test")
        }

        try await server.stop()
    }
}

