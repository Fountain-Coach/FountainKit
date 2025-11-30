import XCTest
@testable import semantic_browser_server

final class Midi2StatusTests: XCTestCase {
    func testStatusWithoutBundle() throws {
        let resp = midi2StatusResponse(env: [:])
        XCTAssertEqual(resp.status, 200)
        let payload = try JSONDecoder().decode(Status.self, from: resp.body)
        XCTAssertTrue(payload.ok)
        XCTAssertEqual(payload.bundle, nil)
        XCTAssertFalse(payload.bundleLoaded)
    }

    func testStatusWithCustomBundleOverridesCapabilities() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("midi2bundle.js")
        // Override the capabilities function to prove bundle executed.
        let js = """
        if (typeof midi2 === 'undefined') { midi2 = {}; }
        midi2.capabilities = function() { return { version: "bundle", scheduler: "custom" }; };
        """
        try js.data(using: .utf8)!.write(to: tmp)
        let resp = midi2StatusResponse(env: ["SB_MIDI2_BUNDLE": tmp.path])
        XCTAssertEqual(resp.status, 200)
        let payload = try JSONDecoder().decode(Status.self, from: resp.body)
        XCTAssertTrue(payload.ok)
        XCTAssertEqual(payload.bundle, tmp.path)
        XCTAssertTrue(payload.bundleLoaded)
        XCTAssertEqual(payload.capabilities?.scheduler, "custom")
    }
}

private struct Status: Codable {
    let ok: Bool
    let bundle: String?
    let bundleLoaded: Bool
    let capabilities: Capabilities?
    let logSize: Int?

    struct Capabilities: Codable {
        let scheduler: String?
        let version: String?
    }
}
