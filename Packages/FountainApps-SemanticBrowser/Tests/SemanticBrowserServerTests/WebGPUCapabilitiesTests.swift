import XCTest
@testable import semantic_browser_server

final class WebGPUCapabilitiesTests: XCTestCase {
    func testDefaultCapabilities() throws {
        let resp = webGPUCapabilitiesResponse(env: [:])
        XCTAssertEqual(resp.status, 200)
        let decoded = try JSONDecoder().decode(Capabilities.self, from: resp.body)
        XCTAssertEqual(decoded.backend, "metal")
        XCTAssertTrue(decoded.supported)
        XCTAssertTrue(decoded.features.contains("timestamp_query"))
    }

    func testCapabilitiesOverrideFromFile() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("caps.json")
        let custom = #"{"backend":"custom","version":"1.2","supported":false,"features":["a"],"limits":{},"timestampQuery":false,"notes":"custom"}"#
        try custom.data(using: .utf8)!.write(to: tmp)
        let resp = webGPUCapabilitiesResponse(env: ["SB_WEBGPU_CAPABILITIES_PATH": tmp.path])
        XCTAssertEqual(resp.status, 200)
        let decoded = try JSONDecoder().decode(Capabilities.self, from: resp.body)
        XCTAssertEqual(decoded.backend, "custom")
        XCTAssertFalse(decoded.supported)
        XCTAssertEqual(decoded.notes, "custom")
    }
}

// Minimal mirror of the manifest shape for decoding tests.
private struct Capabilities: Codable {
    let backend: String
    let version: String
    let supported: Bool
    let features: [String]
    let limits: [String: Int]
    let timestampQuery: Bool
    let notes: String
}
