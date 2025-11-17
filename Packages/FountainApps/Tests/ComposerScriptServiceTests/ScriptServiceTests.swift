import XCTest
@testable import composer_script_service

final class ScriptServiceTests: XCTestCase {
    func testGetScriptAndTagBeats() async throws {
        let handlers = ComposerScriptHandlers()

        let getOut = try await handlers.getScript(.init(path: .init(scriptId: "default"), query: .init(act: nil, scene: nil)))
        guard case let .ok(ok) = getOut, case let .json(doc) = ok.body else {
            XCTFail("Expected OK JSON body"); return
        }
        XCTAssertEqual(doc.scriptId, "default")
        XCTAssertEqual(doc.acts.first?.index, 1)

        let tagReq = Components.Schemas.TagBeatsRequest(act: 1, scene: 1, mode: .emotion, hint: "gentle")
        let tagOut = try await handlers.tagSceneBeats(.init(path: .init(scriptId: "default"), body: .json(tagReq)))
        guard case let .ok(tagOk) = tagOut, case let .json(tagBody) = tagOk.body else {
            XCTFail("Expected OK JSON body"); return
        }
        XCTAssertEqual(tagBody.beats.count, 1)
        XCTAssertEqual(tagBody.beats.first?.label, "emotion")
        XCTAssertEqual(tagBody.beats.first?.emotionTag, "gentle")
    }
}

