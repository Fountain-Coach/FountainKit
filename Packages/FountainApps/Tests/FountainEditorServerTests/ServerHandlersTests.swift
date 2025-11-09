import XCTest
@testable import fountain_editor_service_server
import FountainStoreClient
import OpenAPIRuntime

final class FountainEditorServerHandlersTests: XCTestCase {
    private func makeKernel() throws -> (HTTPKernel, String) {
        let store = FountainStoreClient(client: EmbeddedFountainStoreClient())
        let t = NIOOpenAPIServerTransport()
        let h = FountainEditorHandlers(store: store)
        try h.registerHandlers(on: t, serverURL: URL(string: "/")!)
        return (t.asKernel(), "fountain-editor-test")
    }

    func testScriptETagFlow_andStructure_andPlacements() async throws {
        let (kernel, cid) = try makeKernel()
        // Create with If-Match: "*"
        do {
            let body = Data("INT. ONE\n".utf8)
            let req = HTTPRequest(method: "PUT", path: "/editor/\(cid)/script", headers: [
                "If-Match": "*",
                "Content-Type": "text/plain",
                "Content-Length": String(body.count)
            ], body: body)
            let resp = try await kernel.handle(req)
            XCTAssertEqual(resp.status, 204)
        }
        // GET returns ETag header
        var etag = ""
        do {
            let resp = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/script"))
            XCTAssertEqual(resp.status, 200)
            etag = resp.headers["ETag"] ?? ""
            XCTAssertEqual(etag.count, 8)
        }
        // Mismatch -> 412
        do {
            let body = Data("INT. TWO\n".utf8)
            let req = HTTPRequest(method: "PUT", path: "/editor/\(cid)/script", headers: [
                "If-Match": "deadbeef",
                "Content-Type": "text/plain",
                "Content-Length": String(body.count)
            ], body: body)
            let resp = try await kernel.handle(req)
            XCTAssertEqual(resp.status, 412)
        }
        // Correct If-Match -> 204
        do {
            let body = Data("# Act 1\n## Scene 1\n".utf8)
            let req = HTTPRequest(method: "PUT", path: "/editor/\(cid)/script", headers: [
                "If-Match": etag,
                "Content-Type": "text/plain",
                "Content-Length": String(body.count)
            ], body: body)
            let resp = try await kernel.handle(req)
            XCTAssertEqual(resp.status, 204)
        }
        // GET structure
        do {
            let resp = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/structure"))
            XCTAssertEqual(resp.status, 200)
            // We expect 1 act with 1 scene
            if let data = resp.body, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let acts = json["acts"] as? [[String: Any]], let first = acts.first,
               let scenes = first["scenes"] as? [[String: Any]] {
                XCTAssertEqual(acts.count, 1)
                XCTAssertEqual(scenes.count, 1)
            } else {
                XCTFail("invalid structure json")
            }
        }
        // Placements: create -> list -> patch -> delete
        var placementId = ""
        do {
            let reqBody: [String: Any] = ["anchor": "act1.scene1", "instrumentId": "i1", "order": 1]
            let data = try JSONSerialization.data(withJSONObject: reqBody)
            let resp = try await kernel.handle(HTTPRequest(method: "POST", path: "/editor/\(cid)/placements", headers: [
                "Content-Type": "application/json",
                "Content-Length": String(data.count)
            ], body: data))
            XCTAssertEqual(resp.status, 201)
            if let b = resp.body, let json = try? JSONSerialization.jsonObject(with: b) as? [String: Any] {
                placementId = (json["placementId"] as? String) ?? ""
            }
            XCTAssertFalse(placementId.isEmpty)
        }
        do { // list
            let resp = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/placements?anchor=act1.scene1"))
            XCTAssertEqual(resp.status, 200)
            if let b = resp.body, let arr = try? JSONSerialization.jsonObject(with: b) as? [[String: Any]] {
                XCTAssertEqual(arr.count, 1)
            } else { XCTFail("invalid placements json") }
        }
        do { // patch
            let data = try JSONSerialization.data(withJSONObject: ["order": 2])
            let resp = try await kernel.handle(HTTPRequest(method: "PATCH", path: "/editor/\(cid)/placements/\(placementId)", headers: [
                "Content-Type": "application/json",
                "Content-Length": String(data.count)
            ], body: data))
            XCTAssertEqual(resp.status, 204)
        }
        do { // delete
            let resp = try await kernel.handle(HTTPRequest(method: "DELETE", path: "/editor/\(cid)/placements/\(placementId)"))
            XCTAssertEqual(resp.status, 204)
        }
    }
}

