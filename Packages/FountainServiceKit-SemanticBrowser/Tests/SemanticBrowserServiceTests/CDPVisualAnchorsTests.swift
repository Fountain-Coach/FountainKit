import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import SemanticBrowserService

final class CDPVisualAnchorsTests: XCTestCase {
    func testBrowseReturnsImageAndAnchorsWhenCDPAvailable() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let ws = env["SB_CDP_URL"], let wsURL = URL(string: ws) else {
            throw XCTSkip("SB_CDP_URL not set")
        }
        let svc = SemanticMemoryService()
        let kernel = makeSemanticKernel(service: svc, engine: CDPBrowserEngine(wsURL: wsURL))
        let server = NIOHTTPServer(kernel: kernel)
        let port = try await server.start(port: 0)

        let payload: [String: Any] = [
            "url": "https://example.com",
            "wait": ["strategy": "networkIdle", "networkIdleMs": 500, "maxWaitMs": 8000],
            "mode": "standard",
            "index": ["enabled": false],
            "storeArtifacts": false
        ]
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/browse")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, resp) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)

        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let snapshot = obj?["snapshot"] as? [String: Any]
        let rendered = snapshot?["rendered"] as? [String: Any]
        let image = rendered?["image"] as? [String: Any]
        XCTAssertNotNil(image, "expected screenshot metadata when using CDP engine")
        if let img = image {
            XCTAssertTrue((img["width"] as? Int ?? 0) > 0)
            XCTAssertTrue((img["height"] as? Int ?? 0) > 0)
        }
        // Blocks should include rects (synthetic or real)
        let analysis = obj?["analysis"] as? [String: Any]
        let blocks = analysis?["blocks"] as? [[String: Any]]
        let hasRects = blocks?.contains(where: { ($0["rects"] as? [[String: Any]])?.isEmpty == false }) ?? false
        XCTAssertTrue(hasRects, "expected rect anchors present in analysis blocks")

        try await server.stop()
    }
}

