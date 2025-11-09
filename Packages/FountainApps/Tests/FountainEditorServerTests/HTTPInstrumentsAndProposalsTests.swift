import XCTest
@testable import fountain_editor_service_server
import FountainRuntime
import FountainStoreClient
import Foundation

final class FountainEditorHTTPInstrumentsAndProposalsTests: XCTestCase {
    private func makeKernelAndStore(tmp: URL, corpus: String = "fountain-editor-test") async -> (HTTPKernel, FountainStoreClient) {
        let store = try! DiskFountainStoreClient(rootDirectory: tmp)
        let fc = FountainStoreClient(client: store)
        let transport = NIOOpenAPIServerTransport()
        let handlers = FountainEditorHandlers(store: fc)
        try? handlers.registerHandlers(on: transport, serverURL: URL(string: "/")!)
        return (transport.asKernel(), fc)
    }

    func testInstrumentsCRUD_listCreateGetPatch() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let (kernel, _) = await makeKernelAndStore(tmp: tmp)

        let cid = "fountain-editor"

        // Create instrument
        let createObj: [String: Any] = [
            "name": "Piano",
            "profile": "midi2sampler"
        ]
        let createBody = try JSONSerialization.data(withJSONObject: createObj)
        let createReq = HTTPRequest(method: "POST", path: "/editor/\(cid)/instruments", headers: [
            "Content-Type": "application/json",
            "Content-Length": String(createBody.count)
        ], body: createBody)
        let createResp = try await kernel.handle(createReq)
        XCTAssertEqual(createResp.status, 201)
        let created = try JSONSerialization.jsonObject(with: createResp.body ?? Data()) as? [String: Any]
        let instrumentId = created?["instrumentId"] as? String
        XCTAssertNotNil(instrumentId)

        // List
        let listResp = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/instruments"))
        XCTAssertEqual(listResp.status, 200)
        let list = try JSONSerialization.jsonObject(with: listResp.body ?? Data()) as? [[String: Any]]
        XCTAssertNotNil(list)
        XCTAssertTrue(list!.contains { ($0["instrumentId"] as? String) == instrumentId })

        // Get by id
        let getResp = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/instruments/\(instrumentId!)"))
        XCTAssertEqual(getResp.status, 200)
        let got = try JSONSerialization.jsonObject(with: getResp.body ?? Data()) as? [String: Any]
        XCTAssertEqual(got?["name"] as? String, "Piano")

        // Patch name + programBase
        let patchObj: [String: Any] = [
            "name": "Grand Piano",
            "programBase": 1
        ]
        let patchBody = try JSONSerialization.data(withJSONObject: patchObj)
        let patchReq = HTTPRequest(method: "PATCH", path: "/editor/\(cid)/instruments/\(instrumentId!)", headers: [
            "Content-Type": "application/json",
            "Content-Length": String(patchBody.count)
        ], body: patchBody)
        let patchResp = try await kernel.handle(patchReq)
        XCTAssertEqual(patchResp.status, 204)

        // Verify patch
        let getResp2 = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/instruments/\(instrumentId!)"))
        XCTAssertEqual(getResp2.status, 200)
        let got2 = try JSONSerialization.jsonObject(with: getResp2.body ?? Data()) as? [String: Any]
        XCTAssertEqual(got2?["name"] as? String, "Grand Piano")
        XCTAssertEqual(got2?["programBase"] as? Int, 1)
    }

    func testProposals_composeBlock_apply_advancesETag() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let (kernel, _) = await makeKernelAndStore(tmp: tmp)

        let cid = "fountain-editor"

        // Seed script via If-Match: "*"
        let initial = Data("Hello".utf8)
        let putCreate = HTTPRequest(method: "PUT", path: "/editor/\(cid)/script", headers: [
            "If-Match": "*",
            "Content-Type": "text/plain",
            "Content-Length": String(initial.count)
        ], body: initial)
        let putCreateResp = try await kernel.handle(putCreate)
        XCTAssertEqual(putCreateResp.status, 204)

        // GET ETag
        let getResp = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/script"))
        XCTAssertEqual(getResp.status, 200)
        let etag1 = getResp.headers["ETag"]?.first ?? ""
        XCTAssertEqual(etag1.count, 8)

        // Create proposal composeBlock
        let pObj: [String: Any] = [
            "op": "composeBlock",
            "params": ["text": "World"],
            "anchor": "act1.scene1"
        ]
        let pBody = try JSONSerialization.data(withJSONObject: pObj)
        let pReq = HTTPRequest(method: "POST", path: "/editor/\(cid)/proposals", headers: [
            "Content-Type": "application/json",
            "Content-Length": String(pBody.count)
        ], body: pBody)
        let pResp = try await kernel.handle(pReq)
        XCTAssertEqual(pResp.status, 201)
        let created = try JSONSerialization.jsonObject(with: pResp.body ?? Data()) as? [String: Any]
        let proposalId = created?["proposalId"] as? String
        XCTAssertNotNil(proposalId)

        // Accept decision
        let dObj: [String: Any] = ["decision": "accept"]
        let dBody = try JSONSerialization.data(withJSONObject: dObj)
        let dReq = HTTPRequest(method: "POST", path: "/editor/\(cid)/proposals/\(proposalId!)", headers: [
            "Content-Type": "application/json",
            "Content-Length": String(dBody.count)
        ], body: dBody)
        let dResp = try await kernel.handle(dReq)
        XCTAssertEqual(dResp.status, 200)
        let result = try JSONSerialization.jsonObject(with: dResp.body ?? Data()) as? [String: Any]
        XCTAssertEqual(result?["applied"] as? Bool, true)

        // GET again -> ETag changed and text appended
        let getResp2 = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/script"))
        XCTAssertEqual(getResp2.status, 200)
        let etag2 = getResp2.headers["ETag"]?.first ?? ""
        XCTAssertNotEqual(etag2, etag1)
        let text2 = String(decoding: getResp2.body ?? Data(), as: UTF8.self)
        XCTAssertTrue(text2.contains("Hello"))
        XCTAssertTrue(text2.contains("World"))
    }

    func testProposals_insertScene_anchor_insertsAfterHeading() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let (kernel, _) = await makeKernelAndStore(tmp: tmp)

        let cid = "fountain-editor"

        // Seed script with a first scene heading
        let script = "## Scene One\n\nINT. SCENE ONE — DAY\n\nSome text."
        let putCreate = HTTPRequest(method: "PUT", path: "/editor/\(cid)/script", headers: [
            "If-Match": "*",
            "Content-Type": "text/plain",
            "Content-Length": String(script.utf8.count)
        ], body: Data(script.utf8))
        _ = try await kernel.handle(putCreate)

        // Insert a new scene after act1.scene1
        let pObj: [String: Any] = [
            "op": "insertScene",
            "params": [
                "title": "Inserted",
                "slug": "INT. INSERTED — DAY"
            ],
            "anchor": "act1.scene1"
        ]
        let pBody = try JSONSerialization.data(withJSONObject: pObj)
        let pReq = HTTPRequest(method: "POST", path: "/editor/\(cid)/proposals", headers: [
            "Content-Type": "application/json",
            "Content-Length": String(pBody.count)
        ], body: pBody)
        let pResp = try await kernel.handle(pReq)
        XCTAssertEqual(pResp.status, 201)
        let created = try JSONSerialization.jsonObject(with: pResp.body ?? Data()) as? [String: Any]
        let proposalId = created?["proposalId"] as? String
        XCTAssertNotNil(proposalId)

        // Accept decision
        let dObj: [String: Any] = ["decision": "accept"]
        let dBody = try JSONSerialization.data(withJSONObject: dObj)
        let dReq = HTTPRequest(method: "POST", path: "/editor/\(cid)/proposals/\(proposalId!)", headers: [
            "Content-Type": "application/json",
            "Content-Length": String(dBody.count)
        ], body: dBody)
        let dResp = try await kernel.handle(dReq)
        XCTAssertEqual(dResp.status, 200)

        // Verify new heading appears after the first scene heading
        let getResp2 = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/script"))
        XCTAssertEqual(getResp2.status, 200)
        let text = String(decoding: getResp2.body ?? Data(), as: UTF8.self)
        let idx1 = text.range(of: "## Scene One")?.lowerBound
        let idx2 = text.range(of: "## Inserted")?.lowerBound
        XCTAssertNotNil(idx1)
        XCTAssertNotNil(idx2)
        XCTAssertTrue(idx1! < idx2!)
    }

    func testProposals_renameScene_changesHeading() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let (kernel, _) = await makeKernelAndStore(tmp: tmp)

        let cid = "fountain-editor"

        // Seed script with a first scene heading
        let script = "## Scene One\n\nINT. SCENE ONE — DAY\n\nSome text."
        let putCreate = HTTPRequest(method: "PUT", path: "/editor/\(cid)/script", headers: [
            "If-Match": "*",
            "Content-Type": "text/plain",
            "Content-Length": String(script.utf8.count)
        ], body: Data(script.utf8))
        _ = try await kernel.handle(putCreate)

        // Rename act1.scene1 to "New Title"
        let pObj: [String: Any] = [
            "op": "renameScene",
            "params": ["title": "New Title"],
            "anchor": "act1.scene1"
        ]
        let pBody = try JSONSerialization.data(withJSONObject: pObj)
        let pReq = HTTPRequest(method: "POST", path: "/editor/\(cid)/proposals", headers: [
            "Content-Type": "application/json",
            "Content-Length": String(pBody.count)
        ], body: pBody)
        let pResp = try await kernel.handle(pReq)
        XCTAssertEqual(pResp.status, 201)
        let created = try JSONSerialization.jsonObject(with: pResp.body ?? Data()) as? [String: Any]
        let proposalId = created?["proposalId"] as? String
        XCTAssertNotNil(proposalId)

        // Accept decision
        let dObj: [String: Any] = ["decision": "accept"]
        let dBody = try JSONSerialization.data(withJSONObject: dObj)
        let dReq = HTTPRequest(method: "POST", path: "/editor/\(cid)/proposals/\(proposalId!)", headers: [
            "Content-Type": "application/json",
            "Content-Length": String(dBody.count)
        ], body: dBody)
        let dResp = try await kernel.handle(dReq)
        XCTAssertEqual(dResp.status, 200)

        // Verify heading changed
        let getResp2 = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/script"))
        XCTAssertEqual(getResp2.status, 200)
        let text = String(decoding: getResp2.body ?? Data(), as: UTF8.self)
        XCTAssertTrue(text.contains("## New Title"))
        XCTAssertFalse(text.contains("## Scene One"))
    }

    func testProposals_rewriteRange_replacesSubstring() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let (kernel, _) = await makeKernelAndStore(tmp: tmp)

        let cid = "fountain-editor"

        // Seed plain text
        let script = "Hello world"
        let putCreate = HTTPRequest(method: "PUT", path: "/editor/\(cid)/script", headers: [
            "If-Match": "*",
            "Content-Type": "text/plain",
            "Content-Length": String(script.utf8.count)
        ], body: Data(script.utf8))
        _ = try await kernel.handle(putCreate)

        // Replace "world" with "Editor"
        let pObj: [String: Any] = [
            "op": "rewriteRange",
            "params": ["start": 6, "end": 11, "text": "Editor"]
        ]
        let pBody = try JSONSerialization.data(withJSONObject: pObj)
        let pReq = HTTPRequest(method: "POST", path: "/editor/\(cid)/proposals", headers: [
            "Content-Type": "application/json",
            "Content-Length": String(pBody.count)
        ], body: pBody)
        let pResp = try await kernel.handle(pReq)
        XCTAssertEqual(pResp.status, 201)
        let created = try JSONSerialization.jsonObject(with: pResp.body ?? Data()) as? [String: Any]
        let proposalId = created?["proposalId"] as? String
        XCTAssertNotNil(proposalId)

        // Accept decision
        let dObj: [String: Any] = ["decision": "accept"]
        let dBody = try JSONSerialization.data(withJSONObject: dObj)
        let dReq = HTTPRequest(method: "POST", path: "/editor/\(cid)/proposals/\(proposalId!)", headers: [
            "Content-Type": "application/json",
            "Content-Length": String(dBody.count)
        ], body: dBody)
        let dResp = try await kernel.handle(dReq)
        XCTAssertEqual(dResp.status, 200)

        // Verify text changed
        let getResp2 = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/script"))
        XCTAssertEqual(getResp2.status, 200)
        let text = String(decoding: getResp2.body ?? Data(), as: UTF8.self)
        XCTAssertEqual(text, "Hello Editor")
    }

    func testProposals_moveScene_after_movesBlock() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let (kernel, _) = await makeKernelAndStore(tmp: tmp)

        let cid = "fountain-editor"

        // Seed two scenes
        let script = "## A\n\nINT. A — DAY\n\nfoo\n\n## B\n\nINT. B — DAY\n\nbar\n"
        let putCreate = HTTPRequest(method: "PUT", path: "/editor/\(cid)/script", headers: [
            "If-Match": "*",
            "Content-Type": "text/plain",
            "Content-Length": String(script.utf8.count)
        ], body: Data(script.utf8))
        _ = try await kernel.handle(putCreate)

        // Move A after B
        let pObj: [String: Any] = [
            "op": "moveScene",
            "params": ["targetAnchor": "act1.scene2", "position": "after"],
            "anchor": "act1.scene1"
        ]
        let pBody = try JSONSerialization.data(withJSONObject: pObj)
        let pReq = HTTPRequest(method: "POST", path: "/editor/\(cid)/proposals", headers: [
            "Content-Type": "application/json",
            "Content-Length": String(pBody.count)
        ], body: pBody)
        let pResp = try await kernel.handle(pReq)
        XCTAssertEqual(pResp.status, 201)
        let created = try JSONSerialization.jsonObject(with: pResp.body ?? Data()) as? [String: Any]
        let proposalId = created?["proposalId"] as? String
        XCTAssertNotNil(proposalId)

        // Accept decision
        let dObj: [String: Any] = ["decision": "accept"]
        let dBody = try JSONSerialization.data(withJSONObject: dObj)
        let dReq = HTTPRequest(method: "POST", path: "/editor/\(cid)/proposals/\(proposalId!)", headers: [
            "Content-Type": "application/json",
            "Content-Length": String(dBody.count)
        ], body: dBody)
        let dResp = try await kernel.handle(dReq)
        XCTAssertEqual(dResp.status, 200)

        // Verify order: B before A
        let getResp2 = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/script"))
        XCTAssertEqual(getResp2.status, 200)
        let text = String(decoding: getResp2.body ?? Data(), as: UTF8.self)
        let idxA = text.range(of: "## A")?.lowerBound
        let idxB = text.range(of: "## B")?.lowerBound
        XCTAssertNotNil(idxA)
        XCTAssertNotNil(idxB)
        XCTAssertTrue(idxB! < idxA!)
    }
}
