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
        let created = try JSONSerialization.jsonObject(with: createResp.body) as? [String: Any]
        let instrumentId = created?["instrumentId"] as? String
        XCTAssertNotNil(instrumentId)

        // List
        let listResp = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/instruments"))
        XCTAssertEqual(listResp.status, 200)
        let list = try JSONSerialization.jsonObject(with: listResp.body) as? [[String: Any]]
        XCTAssertNotNil(list)
        XCTAssertTrue(list!.contains { ($0["instrumentId"] as? String) == instrumentId })

        // Get by id
        let getResp = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/instruments/\(instrumentId!)"))
        XCTAssertEqual(getResp.status, 200)
        let got = try JSONSerialization.jsonObject(with: getResp.body) as? [String: Any]
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
        let got2 = try JSONSerialization.jsonObject(with: getResp2.body) as? [String: Any]
        XCTAssertEqual(got2?["name"] as? String, "Grand Piano")
        XCTAssertEqual(got2?["programBase"] as? Int, 1)
    }

    func testProposals_create_withPersonaAndRationale_echoedBack() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let (kernel, _) = await makeKernelAndStore(tmp: tmp)

        let cid = "fountain-editor"
        let pObj: [String: Any] = [
            "op": "composeBlock",
            "params": ["text": "Hello"],
            "authorPersona": "Planner",
            "rationale": "Append a greeting"
        ]
        let pBody = try JSONSerialization.data(withJSONObject: pObj)
        let pReq = HTTPRequest(method: "POST", path: "/editor/\(cid)/proposals", headers: [
            "Content-Type": "application/json",
            "Content-Length": String(pBody.count)
        ], body: pBody)
        let pResp = try await kernel.handle(pReq)
        XCTAssertEqual(pResp.status, 201)
        let created = try JSONSerialization.jsonObject(with: pResp.body) as? [String: Any]
        XCTAssertEqual(created?["authorPersona"] as? String, "Planner")
        XCTAssertEqual(created?["rationale"] as? String, "Append a greeting")
    }

    func testProposals_list_and_get_byId() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let (kernel, _) = await makeKernelAndStore(tmp: tmp)

        let cid = "fountain-editor"
        // Create two proposals
        for t in ["One", "Two"] {
            let pObj: [String: Any] = ["op": "composeBlock", "params": ["text": t]]
            let pBody = try JSONSerialization.data(withJSONObject: pObj)
            let pReq = HTTPRequest(method: "POST", path: "/editor/\(cid)/proposals", headers: [
                "Content-Type": "application/json",
                "Content-Length": String(pBody.count)
            ], body: pBody)
            _ = try await kernel.handle(pReq)
        }

        // List default order desc -> 2 items
        let listResp = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/proposals"))
        XCTAssertEqual(listResp.status, 200)
        let list = try JSONSerialization.jsonObject(with: listResp.body) as? [[String: Any]]
        XCTAssertEqual(list?.count, 2)
        guard let firstId = list?.first?["proposalId"] as? String else { XCTFail("missing id"); return }

        // Get by id
        let getResp = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/proposals/\(firstId)"))
        XCTAssertEqual(getResp.status, 200)
        let detail = try JSONSerialization.jsonObject(with: getResp.body) as? [String: Any]
        XCTAssertEqual(detail?["proposalId"] as? String, firstId)

        // Limit and offset
        let listLimit1 = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/proposals?limit=1"))
        XCTAssertEqual(listLimit1.status, 200)
        let arr1 = try JSONSerialization.jsonObject(with: listLimit1.body) as? [[String: Any]]
        XCTAssertEqual(arr1?.count, 1)
        let listOffset1 = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/proposals?offset=1&limit=1"))
        XCTAssertEqual(listOffset1.status, 200)
        let arr2 = try JSONSerialization.jsonObject(with: listOffset1.body) as? [[String: Any]]
        XCTAssertEqual(arr2?.count, 1)
    }

    func testProposals_applyPatch_invalidRange_appliedFalse() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let (kernel, _) = await makeKernelAndStore(tmp: tmp)
        let cid = "fountain-editor"
        let script = "Hello"
        _ = try await kernel.handle(HTTPRequest(method: "PUT", path: "/editor/\(cid)/script", headers: ["If-Match": "*", "Content-Type": "text/plain", "Content-Length": "5"], body: Data(script.utf8)))
        // invalid end > count
        let pObj: [String: Any] = ["op": "applyPatch", "params": ["edits": [["start": 0, "end": 99, "text": "X"]]]]
        let pBody = try JSONSerialization.data(withJSONObject: pObj)
        let pResp = try await kernel.handle(HTTPRequest(method: "POST", path: "/editor/\(cid)/proposals", headers: ["Content-Type": "application/json", "Content-Length": String(pBody.count)], body: pBody))
        let created = try JSONSerialization.jsonObject(with: pResp.body) as? [String: Any]
        let proposalId = created?["proposalId"] as? String
        let dBody = try JSONSerialization.data(withJSONObject: ["decision": "accept"])
        let dResp = try await kernel.handle(HTTPRequest(method: "POST", path: "/editor/\(cid)/proposals/\(proposalId!)", headers: ["Content-Type": "application/json", "Content-Length": String(dBody.count)], body: dBody))
        XCTAssertEqual(dResp.status, 200)
        let result = try JSONSerialization.jsonObject(with: dResp.body) as? [String: Any]
        XCTAssertEqual(result?["applied"] as? Bool, false)
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
        let etag1 = getResp.headers["ETag"] ?? ""
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
        let created = try JSONSerialization.jsonObject(with: pResp.body) as? [String: Any]
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
        let result = try JSONSerialization.jsonObject(with: dResp.body) as? [String: Any]
        XCTAssertEqual(result?["applied"] as? Bool, true)

        // GET again -> ETag changed and text appended
        let getResp2 = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/script"))
        XCTAssertEqual(getResp2.status, 200)
        let etag2 = getResp2.headers["ETag"] ?? ""
        XCTAssertNotEqual(etag2, etag1)
        let text2 = String(decoding: getResp2.body, as: UTF8.self)
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
        let created = try JSONSerialization.jsonObject(with: pResp.body) as? [String: Any]
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
        let text = String(decoding: getResp2.body, as: UTF8.self)
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
        let created = try JSONSerialization.jsonObject(with: pResp.body) as? [String: Any]
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
        let text = String(decoding: getResp2.body, as: UTF8.self)
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
        let created = try JSONSerialization.jsonObject(with: pResp.body) as? [String: Any]
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
        let text = String(decoding: getResp2.body, as: UTF8.self)
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
        let created = try JSONSerialization.jsonObject(with: pResp.body) as? [String: Any]
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
        let text = String(decoding: getResp2.body, as: UTF8.self)
        let idxA = text.range(of: "## A")?.lowerBound
        let idxB = text.range(of: "## B")?.lowerBound
        XCTAssertNotNil(idxA)
        XCTAssertNotNil(idxB)
        XCTAssertTrue(idxB! < idxA!)
    }

    func testProposals_splitScene_splitsAtLine() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let (kernel, _) = await makeKernelAndStore(tmp: tmp)

        let cid = "fountain-editor"

        // Seed one scene with two content lines
        let script = "## Alpha\n\nINT. ALPHA — DAY\n\nFirst\nSecond\n"
        let putCreate = HTTPRequest(method: "PUT", path: "/editor/\(cid)/script", headers: [
            "If-Match": "*",
            "Content-Type": "text/plain",
            "Content-Length": String(script.utf8.count)
        ], body: Data(script.utf8))
        _ = try await kernel.handle(putCreate)

        // Split after first content line
        let pObj: [String: Any] = [
            "op": "splitScene",
            "params": ["newTitle": "Beta", "atLine": 2],
            "anchor": "act1.scene1"
        ]
        let pBody = try JSONSerialization.data(withJSONObject: pObj)
        let pReq = HTTPRequest(method: "POST", path: "/editor/\(cid)/proposals", headers: [
            "Content-Type": "application/json",
            "Content-Length": String(pBody.count)
        ], body: pBody)
        let pResp = try await kernel.handle(pReq)
        XCTAssertEqual(pResp.status, 201)
        let created = try JSONSerialization.jsonObject(with: pResp.body) as? [String: Any]
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

        // Verify headings and content distribution
        let getResp2 = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/script"))
        XCTAssertEqual(getResp2.status, 200)
        let text = String(decoding: getResp2.body, as: UTF8.self)
        // Alpha then Beta
        let idxAlpha = text.range(of: "## Alpha")?.lowerBound
        let idxBeta = text.range(of: "## Beta")?.lowerBound
        XCTAssertNotNil(idxAlpha); XCTAssertNotNil(idxBeta); XCTAssertTrue(idxAlpha! < idxBeta!)
        // First should remain with Alpha; Second should be under Beta
        // Check by relative ordering
        let idxFirst = text.range(of: "First")?.lowerBound
        let idxSecond = text.range(of: "Second")?.lowerBound
        XCTAssertNotNil(idxFirst); XCTAssertNotNil(idxSecond)
        XCTAssertTrue(idxFirst! < idxBeta!)
        XCTAssertTrue(idxSecond! > idxBeta!)
    }

    func testProposals_applyPatch_multipleRangeEdits() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let (kernel, _) = await makeKernelAndStore(tmp: tmp)

        let cid = "fountain-editor"
        let script = "Hello World Again"
        let putCreate = HTTPRequest(method: "PUT", path: "/editor/\(cid)/script", headers: [
            "If-Match": "*",
            "Content-Type": "text/plain",
            "Content-Length": String(script.utf8.count)
        ], body: Data(script.utf8))
        _ = try await kernel.handle(putCreate)

        // Apply two edits: delete " Again" and replace World->Editor
        let edits: [[String: Any]] = [
            ["start": 11, "end": 17, "text": ""],
            ["start": 6, "end": 11, "text": "Editor"]
        ]
        let pObj: [String: Any] = ["op": "applyPatch", "params": ["edits": edits]]
        let pBody = try JSONSerialization.data(withJSONObject: pObj)
        let pReq = HTTPRequest(method: "POST", path: "/editor/\(cid)/proposals", headers: [
            "Content-Type": "application/json",
            "Content-Length": String(pBody.count)
        ], body: pBody)
        let pResp = try await kernel.handle(pReq)
        XCTAssertEqual(pResp.status, 201)
        let created = try JSONSerialization.jsonObject(with: pResp.body) as? [String: Any]
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

        let getResp2 = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/script"))
        XCTAssertEqual(getResp2.status, 200)
        let textOut = String(decoding: getResp2.body, as: UTF8.self)
        XCTAssertEqual(textOut, "Hello Editor")
    }

    func testSessions_create_and_patch() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let (kernel, _) = await makeKernelAndStore(tmp: tmp)

        // Create
        let cObj: [String: Any] = ["corpusId": "fountain-editor"]
        let cBody = try JSONSerialization.data(withJSONObject: cObj)
        let cResp = try await kernel.handle(HTTPRequest(method: "POST", path: "/editor/sessions", headers: ["Content-Type": "application/json", "Content-Length": String(cBody.count)], body: cBody))
        XCTAssertEqual(cResp.status, 201)
        let created = try JSONSerialization.jsonObject(with: cResp.body) as? [String: Any]
        let sid = created?["sessionId"] as? String
        XCTAssertNotNil(sid)

        // Patch (no body change)
        let now = ISO8601DateFormatter().string(from: Date())
        let pBody = try JSONSerialization.data(withJSONObject: ["lastMessageAt": now])
        let pResp = try await kernel.handle(HTTPRequest(method: "PATCH", path: "/editor/sessions/\(sid!)", headers: ["Content-Type": "application/json", "Content-Length": String(pBody.count)], body: pBody))
        XCTAssertEqual(pResp.status, 204)
    }

    func testHealth_structure_preview_sessionsList() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let (kernel, _) = await makeKernelAndStore(tmp: tmp)

        // Health
        let h = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/health"))
        XCTAssertEqual(h.status, 200)

        // Seed script
        let cid = "fountain-editor"
        let text = "## S1\n\nINT. S1 — DAY\n"
        _ = try await kernel.handle(HTTPRequest(method: "PUT", path: "/editor/\(cid)/script", headers: ["If-Match": "*", "Content-Type": "text/plain", "Content-Length": String(text.utf8.count)], body: Data(text.utf8)))

        // Structure
        let st = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/structure"))
        XCTAssertEqual(st.status, 200)

        // Preview parse
        let pv = try await kernel.handle(HTTPRequest(method: "POST", path: "/editor/preview/parse", headers: ["Content-Type": "text/plain", "Content-Length": "6"], body: Data("Hello!".utf8)))
        XCTAssertEqual(pv.status, 200)

        // Sessions list (empty array acceptable)
        let sl = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/sessions"))
        XCTAssertEqual(sl.status, 200)
    }

    func testTyped404s_proposalAndSession() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let (kernel, _) = await makeKernelAndStore(tmp: tmp)
        let cid = "fountain-editor"

        // Proposal not found
        let p = try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/proposals/00000000-0000-0000-0000-000000000000"))
        XCTAssertEqual(p.status, 404)
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: p.body) as? [String: Any])

        // Session not found
        let now = ISO8601DateFormatter().string(from: Date())
        let sBody = try JSONSerialization.data(withJSONObject: ["lastMessageAt": now])
        let s = try await kernel.handle(HTTPRequest(method: "PATCH", path: "/editor/sessions/00000000-0000-0000-0000-000000000000", headers: ["Content-Type": "application/json", "Content-Length": String(sBody.count)], body: sBody))
        XCTAssertEqual(s.status, 404)
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: s.body) as? [String: Any])
    }
}
