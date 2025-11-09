import XCTest
@testable import fountain_editor_service_server
import FountainRuntime
import FountainStoreClient
import Foundation

final class FountainEditorHTTPETagTests: XCTestCase {
    private func makeKernelAndStore(tmp: URL, corpus: String = "fountain-editor-test") async -> (HTTPKernel, FountainStoreClient) {
        let store = try! DiskFountainStoreClient(rootDirectory: tmp)
        let fc = FountainStoreClient(client: store)
        let transport = NIOOpenAPIServerTransport()
        let handlers = FountainEditorHandlers(store: fc)
        try? handlers.registerHandlers(on: transport, serverURL: URL(string: "/")!)
        return (transport.asKernel(), fc)
    }

    func testScriptPutIfMatchFlow_204And412() async throws {
        // Setup store/kernel under a temporary directory
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let (kernel, _) = await makeKernelAndStore(tmp: tmp)

        let cid = "fountain-editor"

        // 1) Create with If-Match: "*"
        let body1 = Data("Hello".utf8)
        var req1 = HTTPRequest(method: "PUT", path: "/editor/\(cid)/script", headers: [
            "If-Match": "*",
            "Content-Type": "text/plain",
            "Content-Length": String(body1.count)
        ], body: body1)
        let resp1 = try await kernel.handle(req1)
        XCTAssertEqual(resp1.status, 204)

        // 2) GET -> obtain ETag and body
        let getReq = HTTPRequest(method: "GET", path: "/editor/\(cid)/script")
        let getResp = try await kernel.handle(getReq)
        XCTAssertEqual(getResp.status, 200)
        let etag1 = getResp.headers["ETag"]?.first ?? ""
        XCTAssertEqual(etag1.count, 8)
        let text1 = String(decoding: getResp.body ?? Data(), as: UTF8.self)
        XCTAssertEqual(text1, "Hello")

        // 3) Mismatched If-Match -> 412
        let bodyBad = Data("Hello again".utf8)
        let badReq = HTTPRequest(method: "PUT", path: "/editor/\(cid)/script", headers: [
            "If-Match": "deadbeef",
            "Content-Type": "text/plain",
            "Content-Length": String(bodyBad.count)
        ], body: bodyBad)
        let badResp = try await kernel.handle(badReq)
        XCTAssertEqual(badResp.status, 412)

        // 4) Correct If-Match -> update 204
        let body2 = Data("Hello world!".utf8)
        let req2 = HTTPRequest(method: "PUT", path: "/editor/\(cid)/script", headers: [
            "If-Match": etag1,
            "Content-Type": "text/plain",
            "Content-Length": String(body2.count)
        ], body: body2)
        let resp2 = try await kernel.handle(req2)
        XCTAssertEqual(resp2.status, 204)

        // 5) GET again -> ETag changed and body updated
        let getResp2 = try await kernel.handle(getReq)
        XCTAssertEqual(getResp2.status, 200)
        let etag2 = getResp2.headers["ETag"]?.first ?? ""
        XCTAssertEqual(etag2.count, 8)
        XCTAssertNotEqual(etag2, etag1)
        let text2 = String(decoding: getResp2.body ?? Data(), as: UTF8.self)
        XCTAssertEqual(text2, "Hello world!")
    }

    func testPutRequiresIfMatchHeader_400() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let (kernel, _) = await makeKernelAndStore(tmp: tmp)
        let cid = "fountain-editor"
        let body = Data("Text".utf8)
        let req = HTTPRequest(method: "PUT", path: "/editor/\(cid)/script", headers: [
            "Content-Type": "text/plain",
            "Content-Length": String(body.count)
        ], body: body)
        let resp = try await kernel.handle(req)
        XCTAssertEqual(resp.status, 400)
    }
}

