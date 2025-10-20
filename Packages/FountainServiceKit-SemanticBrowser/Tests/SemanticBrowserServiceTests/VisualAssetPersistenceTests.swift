import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import SemanticBrowserService

final class VisualAssetPersistenceTests: XCTestCase {
    func testAssetIsPersistedAndFetchable() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let ws = env["SB_CDP_URL"], let wsURL = URL(string: ws) else {
            throw XCTSkip("SB_CDP_URL not set")
        }
        let svc = SemanticBrowserService.SemanticMemoryService()
        let kernel = makeSemanticKernel(service: svc, engine: CDPBrowserEngine(wsURL: wsURL))
        let server = NIOHTTPServer(kernel: kernel)
        let port = try await server.start(port: 0)

        // Trigger browse to capture screenshot and persist asset
        let payload: [String: Any] = [
            "url": "https://example.com",
            "wait": ["strategy": "networkIdle", "networkIdleMs": 300, "maxWaitMs": 6000],
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

        // Parse response to get imageId
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let snapshot = obj?["snapshot"] as? [String: Any]
        let rendered = snapshot?["rendered"] as? [String: Any]
        guard let image = rendered?["image"] as? [String: Any], let imageId = image["imageId"] as? String else {
            return XCTFail("expected image metadata in snapshot")
        }

        // Fetch the asset via dev route
        let (pngData, assetResp) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/assets/\(imageId).png")!)
        XCTAssertEqual((assetResp as? HTTPURLResponse)?.statusCode, 200)
        if let http = assetResp as? HTTPURLResponse {
            XCTAssertEqual(http.allHeaderFields["Content-Type"] as? String, "image/png")
        }
        XCTAssertGreaterThan(pngData.count, 100)

        try await server.stop()
    }
}
