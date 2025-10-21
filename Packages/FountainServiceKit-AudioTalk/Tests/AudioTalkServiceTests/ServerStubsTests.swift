import XCTest
import OpenAPIRuntime
@testable import AudioTalkService

final class ServerStubsTests: XCTestCase {
    func testHealthOK() async throws {
        let api = AudioTalkOpenAPI(state: AudioTalkState())
        let out = try await api.getAudioTalkHealth(Operations.getAudioTalkHealth.Input())
        switch out {
        case .ok:
            XCTAssertTrue(true)
        case .undocumented(let status, _):
            XCTAssertEqual(status, 200)
        default:
            XCTFail("Expected .ok or 200 undocumented from getAudioTalkHealth")
        }
    }

    func testDictionaryUpsertAndList() async throws {
        let api = AudioTalkOpenAPI(state: AudioTalkState())
        let items = [Components.Schemas.DictionaryItem(token: "warm", value: "timbre:warmth:+0.4", description: nil)]
        let req = Components.Schemas.DictionaryUpsertRequest(items: items)
        let up = try await api.upsertDictionary(.init(body: .json(req)))
        guard case .ok(let upOK) = up, case .json(let resp) = upOK.body else { return XCTFail("Expected ok json") }
        XCTAssertEqual(resp.updated, 1)
        let list = try await api.listDictionary(.init())
        guard case .ok(let listOK) = list, case .json(let li) = listOK.body else { return XCTFail("Expected ok json list") }
        XCTAssertEqual(li.items.first?.token, "warm")
    }

    func testMacroCreatePromote() async throws {
        let api = AudioTalkOpenAPI(state: AudioTalkState())
        let plan = Components.Schemas.Plan(ops: [], meta: nil)
        let mReq = Components.Schemas.MacroCreateRequest(id: "m1", plan: plan)
        let created = try await api.createMacro(.init(body: .json(mReq)))
        guard case .created(let c) = created, case .json(let macro) = c.body else { return XCTFail("Expected created json") }
        XCTAssertEqual(macro.id, "m1")
        let promoted = try await api.promoteMacro(.init(path: .init(macroId: "m1")))
        guard case .ok(let p) = promoted, case .json(let pm) = p.body else { return XCTFail("Expected ok json") }
        XCTAssertEqual(pm.state, .approved)
    }

    func testNotationETagFlow() async throws {
        let api = AudioTalkOpenAPI(state: AudioTalkState())
        // Create session
        let cs = try await api.createNotationSession(.init())
        guard case .created(let c) = cs, case .json(let sess) = c.body else { return XCTFail("expected created session") }
        let id = sess.id
        // Get source, capture ETag
        let get1 = try await api.getLilySource(.init(path: .init(id: id)))
        guard case .ok(let ok1) = get1, let etag1 = ok1.headers.ETag else { return XCTFail("expected ETag") }
        // Mismatched If-Match should 412
        let putBad = try await api.putLilySource(.init(path: .init(id: id), headers: .init(If_hyphen_Match: "wrong"), body: .plainText(HTTPBody("% bad"))))
        guard case .preconditionFailed = putBad else { return XCTFail("expected 412") }
        // Correct If-Match succeeds with new ETag
        let putGood = try await api.putLilySource(.init(path: .init(id: id), headers: .init(If_hyphen_Match: etag1), body: .plainText(HTTPBody("% lily \n c'4"))))
        guard case .ok(let ok2) = putGood, let etag2 = ok2.headers.ETag else { return XCTFail("expected ok with etag") }
        XCTAssertNotEqual(etag1, etag2)
        // Get reflects new source and ETag
        let get2 = try await api.getLilySource(.init(path: .init(id: id)))
        guard case .ok(let ok3) = get2, let etag3 = ok3.headers.ETag else { return XCTFail("expected ok with etag") }
        XCTAssertEqual(etag2, etag3)
    }

    func testScreenplayETagFlow() async throws {
        let api = AudioTalkOpenAPI(state: AudioTalkState())
        let cs = try await api.createScreenplaySession(.init())
        guard case .created(let c) = cs, case .json(let sess) = c.body else { return XCTFail("expected created session") }
        let id = sess.id
        let get1 = try await api.getScreenplaySource(.init(path: .init(id: id)))
        guard case .ok(let ok1) = get1, let etag1 = ok1.headers.ETag else { return XCTFail("expected etag") }
        let putBad = try await api.putScreenplaySource(.init(path: .init(id: id), headers: .init(If_hyphen_Match: "wrong"), body: .plainText(HTTPBody("INT. ROOM - DAY"))))
        guard case .preconditionFailed = putBad else { return XCTFail("expected 412") }
        let putGood = try await api.putScreenplaySource(.init(path: .init(id: id), headers: .init(If_hyphen_Match: etag1), body: .plainText(HTTPBody("INT. ROOM - NIGHT"))))
        guard case .ok(let ok2) = putGood, let etag2 = ok2.headers.ETag else { return XCTFail("expected ok with etag") }
        XCTAssertNotEqual(etag1, etag2)
    }

    func testIntentParseTypedPlan() async throws {
        let api = AudioTalkOpenAPI(state: AudioTalkState())
        let req = Components.Schemas.IntentRequest(phrase: "legato crescendo", context: nil)
        let resp = try await api.parseIntent(.init(body: .json(req)))
        guard case .ok(let ok) = resp, case .json(let body) = ok.body else { return XCTFail("expected ok json") }
        XCTAssertEqual(body.tokens?.count ?? 0, 2)
        XCTAssertEqual(body.plan.ops.count, 2)
        XCTAssertEqual(body.plan.ops.first?.kind, .token)
    }

    func testUMPSendValidation() async throws {
        let api = AudioTalkOpenAPI(state: AudioTalkState())
        let good = Components.Schemas.UMPBatch(items: [.init(jr_timestamp: nil, host_time_ns: nil, ump: "40196000")])
        let accepted = try await api.sendUMPBatch(.init(path: .init(session: "s1"), body: .json(good)))
        guard case .accepted = accepted else { return XCTFail("expected 202 accepted") }
        let bad = Components.Schemas.UMPBatch(items: [.init(jr_timestamp: nil, host_time_ns: nil, ump: "Z1")])
        let rejected = try await api.sendUMPBatch(.init(path: .init(session: "s1"), body: .json(bad)))
        guard case .badRequest = rejected else { return XCTFail("expected 400 bad request") }
    }

    func testSSEEndpoints() async throws {
        let api = AudioTalkOpenAPI(state: AudioTalkState())
        // parseIntentStream returns 202 with text/event-stream body
        let intentOut = try await api.parseIntentStream(.init(body: .json(.init(phrase: "p", context: nil))))
        guard case .accepted(let acc) = intentOut else { return XCTFail("expected 202 accepted") }
        switch acc.body { case .text_event_hyphen_stream: break }
        // streamJournal returns 200 with text/event-stream body
        let journalOut = try await api.streamJournal(.init())
        guard case .ok(let ok) = journalOut else { return XCTFail("expected 200 ok") }
        switch ok.body { case .text_event_hyphen_stream: break }
    }
}
