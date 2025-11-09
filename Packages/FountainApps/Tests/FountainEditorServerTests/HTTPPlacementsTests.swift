import XCTest
@testable import fountain_editor_service_server
import FountainRuntime
import FountainStoreClient
import Foundation

final class FountainEditorHTTPPlacementsTests: XCTestCase {
    private func makeKernelAndStore(tmp: URL, corpus: String = "fountain-editor-test") async -> (HTTPKernel, FountainStoreClient) {
        let store = try! DiskFountainStoreClient(rootDirectory: tmp)
        let fc = FountainStoreClient(client: store)
        let transport = NIOOpenAPIServerTransport()
        let handlers = FountainEditorHandlers(store: fc)
        try? handlers.registerHandlers(on: transport, serverURL: URL(string: "/")!)
        return (transport.asKernel(), fc)
    }

    func testPlacementsCRUDPersists() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let (kernel, store) = await makeKernelAndStore(tmp: tmp)
        let cid = "fountain-editor"
        let anchor = "act1.scene1"

        // Create placement
        let createObj: [String: Any] = ["anchor": anchor, "instrumentId": "instA", "order": 1]
        let createBody = try JSONSerialization.data(withJSONObject: createObj)
        let createReq = HTTPRequest(method: "POST", path: "/editor/\(cid)/placements", headers: [
            "Content-Type": "application/json",
            "Content-Length": String(createBody.count)
        ], body: createBody)
        let createResp = try await kernel.handle(createReq)
        XCTAssertEqual(createResp.status, 201)
        let created = try JSONSerialization.jsonObject(with: createResp.body ?? Data()) as? [String: Any]
        let pid = created?["placementId"] as? String
        XCTAssertNotNil(pid)

        // List by anchor -> 1
        let listResp = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/placements?anchor=\(anchor)"))
        XCTAssertEqual(listResp.status, 200)
        let list = try JSONSerialization.jsonObject(with: listResp.body ?? Data()) as? [[String: Any]]
        XCTAssertEqual(list?.count, 1)

        // Update order -> 2
        let updObj: [String: Any] = ["order": 2]
        let updBody = try JSONSerialization.data(withJSONObject: updObj)
        let updReq = HTTPRequest(method: "PATCH", path: "/editor/\(cid)/placements/\(pid!)", headers: [
            "Content-Type": "application/json",
            "Content-Length": String(updBody.count)
        ], body: updBody)
        let updResp = try await kernel.handle(updReq)
        XCTAssertEqual(updResp.status, 204)

        // List again -> order 2
        let listResp2 = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/placements?anchor=\(anchor)"))
        XCTAssertEqual(listResp2.status, 200)
        let list2 = try JSONSerialization.jsonObject(with: listResp2.body ?? Data()) as? [[String: Any]]
        XCTAssertEqual(list2?.count, 1)
        XCTAssertEqual(list2?.first?["order"] as? Int, 2)

        // Delete
        let delResp = try await kernel.handle(HTTPRequest(method: "DELETE", path: "/editor/\(cid)/placements/\(pid!)"))
        XCTAssertEqual(delResp.status, 204)

        // List again -> empty
        let listResp3 = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/placements?anchor=\(anchor)"))
        XCTAssertEqual(listResp3.status, 200)
        let list3 = try JSONSerialization.jsonObject(with: listResp3.body ?? Data()) as? [[String: Any]]
        XCTAssertEqual(list3?.count, 0)

        // Confirm persisted segment exists (array is empty after delete)
        let pidPage = "editor:placements:\(cid)"
        let segId = "\(pidPage):editor.placements.\(anchor)"
        let segData = try await store.getDoc(corpusId: cid, collection: "segments", id: segId)
        XCTAssertNotNil(segData)
    }
}

