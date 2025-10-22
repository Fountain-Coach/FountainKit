import XCTest
import OpenAPIRuntime
@testable import AudioTalkService

final class FlowsTests: XCTestCase {
    func testScreenplayToNotationApplyAndCueSheetCSV() async throws {
        let api = AudioTalkOpenAPI(state: AudioTalkState())
        // Create screenplay session and put source with a tag
        let scp = try await api.createScreenplaySession(.init())
        guard case .created(let scpCrt) = scp, case .json(let scpSess) = scpCrt.body else { return XCTFail("expected created") }
        let sid = scpSess.id
        let putSrc = try await api.putScreenplaySource(.init(path: .init(id: sid), headers: .init(If_hyphen_Match: nil), body: .plainText(HTTPBody("INT. ROOM - DAY\n[[AudioTalk: f]]\n"))))
        guard case .ok = putSrc else { return XCTFail("expected ok on put source") }
        // Parse screenplay and map cues
        let parsed = try await api.parseScreenplay(.init(path: .init(id: sid)))
        guard case .ok(let okP) = parsed, case .json(let parseBody) = okP.body else { return XCTFail("expected ok json") }
        XCTAssertGreaterThan(parseBody.model.notes?.count ?? 0, 0)
        let mapped = try await api.mapScreenplayCues(.init(path: .init(id: sid), body: .json(.init(theme_table: nil, hints: nil))))
        guard case .ok(let okM) = mapped, case .json(let cuesPayload) = okM.body else { return XCTFail("expected ok json") }
        XCTAssertGreaterThan(cuesPayload.cues?.count ?? 0, 0)
        // Create notation session and apply cues (no If-Match header)
        let ns = try await api.createNotationSession(.init())
        guard case .created(let nsCrt) = ns, case .json(let notationSess) = nsCrt.body else { return XCTFail("expected created notation") }
        let nid = notationSess.id
        let applyReq = Components.Schemas.ApplyCuesRequest(notation_session_id: nid, options: nil)
        let applied = try await api.applyScreenplayCuesToNotation(.init(path: .init(id: sid), headers: .init(If_hyphen_Match: nil), body: .json(applyReq)))
        guard case .ok(let okA) = applied, case .json(let appBody) = okA.body else { return XCTFail("expected ok json apply") }
        XCTAssertGreaterThan(appBody.scoreETag?.count ?? 0, 0)
        // Lily source should now contain a dynamic mark (\f)
        let lily = try await api.getLilySource(.init(path: .init(id: nid)))
        guard case .ok(let okL) = lily, case .plainText(let body) = okL.body else { return XCTFail("expected plain text") }
        let text = try await String(collecting: body, upTo: 1<<20)
        XCTAssertTrue(text.contains("% AudioTalk Cue"))
        XCTAssertTrue(text.contains("\\f") || text.contains("{ f }"), "Expected dynamic content in lily output: \(text)")
        // Cue sheet CSV variant
        let csvOut = try await api.getCueSheet(.init(path: .init(id: sid), query: .init(format: .csv)))
        guard case .ok(let okCSV) = csvOut, case .csv(let csvBody) = okCSV.body else { return XCTFail("expected csv body") }
        let csv = try await String(collecting: csvBody, upTo: 1<<20)
        XCTAssertTrue(csv.contains("cue_id,label,scene,line,character,ops"))
        // PDF variant should return some bytes
        let pdfOut = try await api.getCueSheet(.init(path: .init(id: sid), query: .init(format: .pdf)))
        guard case .ok(let okPDF) = pdfOut, case .pdf(let pdfBody) = okPDF.body else { return XCTFail("expected pdf body") }
        let pdfData = try await Data(collecting: pdfBody, upTo: 1<<20)
        XCTAssertGreaterThan(pdfData.count, 0)
    }

    func testUMPEventsPersistenceAndListing() async throws {
        let api = AudioTalkOpenAPI(state: AudioTalkState())
        let sess = "UMP-TEST-1"
        let batch = Components.Schemas.UMPBatch(items: [.init(jr_timestamp: 123, host_time_ns: 456, ump: "40196000")])
        let sent = try await api.sendUMPBatch(.init(path: .init(session: sess), body: .json(batch)))
        guard case .accepted = sent else { return XCTFail("expected 202 accepted") }
        let listed = try await api.listUMPEvents(.init(path: .init(session: sess)))
        guard case .ok(let ok) = listed, case .json(let body) = ok.body else { return XCTFail("expected ok json list") }
        XCTAssertGreaterThan(body.items.count, 0)
        XCTAssertEqual(body.items.first?.ump, "40196000")
    }

    func testParseScreenplayStreamSSE() async throws {
        let api = AudioTalkOpenAPI(state: AudioTalkState())
        let scp = try await api.createScreenplaySession(.init())
        guard case .created(let scpCrt) = scp, case .json(let scpSess) = scpCrt.body else { return XCTFail("expected created") }
        let sid = scpSess.id
        _ = try await api.putScreenplaySource(.init(path: .init(id: sid), headers: .init(If_hyphen_Match: nil), body: .plainText(HTTPBody("INT. ROOM - DAY\n= beat\n[[AudioTalk: f]]\n"))))
        let out = try await api.parseScreenplayStream(.init(path: .init(id: sid)))
        guard case .accepted(let acc) = out else { return XCTFail("expected 202 accepted") }
        switch acc.body { case .text_event_hyphen_stream: break }
    }
}
