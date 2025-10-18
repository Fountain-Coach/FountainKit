import XCTest
@testable import SpeechAtlasService
import FountainStoreClient

final class SpeechAtlasScriptTests: XCTestCase {

    func testSceneScriptMarkdownReadable() async throws {
        let sample = """
        As You Like It
        **** ACT I ****
        **** SCENE II. Lawn before the Duke's palace. ****
        CELIA
        Yonder, sure, they are coming: let us now stay and see it.
        ORLANDO
        I beseech you, punish me not with your hard thoughts.
        """

        let dir = NSTemporaryDirectory()
        let path = (dir as NSString).appendingPathComponent("test-play.fountain")
        try sample.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        setenv("FOUNTAIN_SOURCE_PATH", path, 1)
        unsetenv("SPEAKER_MAP")
        let handler = SpeechAtlasHandlers(store: FountainStoreClient(client: EmbeddedFountainStoreClient()))
        let req = Components.Schemas.SceneScriptRequest(
            act: "I",
            scene: "II",
            layout: .readable,
            format: .json,
            group_consecutive: true
        )
        let out = try await handler.speechesScript(.init(body: .json(req)))
        guard case let .ok(ok) = out, case let .json(payload) = ok.body else {
            return XCTFail("Expected 200 JSON response")
        }
        XCTAssertTrue(payload.result.header?.hasPrefix("Act I Scene II – Lawn before the Duke's palace") == true)
        let speakers = payload.result.blocks?.map { $0.speaker } ?? []
        XCTAssertTrue(speakers.contains("CELIA"))
        XCTAssertTrue(speakers.contains("ORLANDO"))
    }

    func testSceneScriptJsonWithAliasMapping() async throws {
        let sample = """
        As You Like It
        **** ACT I ****
        **** SCENE II. Lawn before the Duke's palace. ****
        CELIA
        Yonder, sure, they are coming.
        """

        let dir = NSTemporaryDirectory()
        let path = (dir as NSString).appendingPathComponent("test-play.fountain")
        try sample.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        setenv("FOUNTAIN_SOURCE_PATH", path, 1)
        setenv("SPEAKER_MAP", "celia=Lady Celia", 1)
        let handler = SpeechAtlasHandlers(store: FountainStoreClient(client: EmbeddedFountainStoreClient()))
        let req = Components.Schemas.SceneScriptRequest(
            act: "I",
            scene: "II",
            layout: .readable,
            format: .json,
            group_consecutive: true
        )
        let out = try await handler.speechesScript(.init(body: .json(req)))
        guard case let .ok(ok) = out, case let .json(payload) = ok.body else {
            return XCTFail("Expected 200 JSON response")
        }
        let firstSpeaker = payload.result.blocks?.first?.speaker
        XCTAssertEqual(firstSpeaker, "Lady Celia")
    }

    func testSceneScriptJsonScreenplayLayoutBlocks() async throws {
        let sample = """
        As You Like It
        **** ACT I ****
        **** SCENE II. Lawn before the Duke's palace. ****
        CELIA
        First line.
        CELIA
        Second line.
        ORLANDO
        Third line.
        """

        let dir = NSTemporaryDirectory()
        let path = (dir as NSString).appendingPathComponent("test-play.fountain")
        try sample.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        setenv("FOUNTAIN_SOURCE_PATH", path, 1)
        let handler = SpeechAtlasHandlers(store: FountainStoreClient(client: EmbeddedFountainStoreClient()))
        let req = Components.Schemas.SceneScriptRequest(
            act: "I",
            scene: "II",
            layout: .screenplay,
            format: .json,
            group_consecutive: true
        )
        let out = try await handler.speechesScript(.init(body: .json(req)))
        guard case let .ok(ok) = out, case let .json(payload) = ok.body else {
            return XCTFail("Expected 200 JSON response")
        }
        let blocks = payload.result.blocks ?? []
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].speaker, "CELIA")
        XCTAssertEqual(blocks[1].speaker, "CELIA")
        XCTAssertEqual(blocks[2].speaker, "ORLANDO")
    }

    func testSceneScriptMarkdownSpeakerOrder() async throws {
        let sample = """
        As You Like It
        **** ACT I ****
        **** SCENE II. Lawn before the Duke's palace. ****
        CELIA
        Yonder, sure, they are coming.
        ORLANDO
        I beseech you, punish me not with your hard thoughts.
        """

        let dir = NSTemporaryDirectory()
        let path = (dir as NSString).appendingPathComponent("test-play.fountain")
        try sample.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        setenv("FOUNTAIN_SOURCE_PATH", path, 1)
        unsetenv("SPEAKER_MAP")
        let handler = SpeechAtlasHandlers(store: FountainStoreClient(client: EmbeddedFountainStoreClient()))
        let req = Components.Schemas.SceneScriptRequest(
            act: "I",
            scene: "II",
            layout: .readable,
            format: .markdown,
            group_consecutive: true
        )
        let out = try await handler.speechesScript(.init(body: .json(req)))
        guard case let .ok(ok) = out, case let .json(payload) = ok.body else {
            return XCTFail("Expected 200 JSON response")
        }
        let md = payload.result.markdown ?? ""
        let p1 = md.range(of: "**CELIA**")?.lowerBound
        let p2 = md.range(of: "**ORLANDO**")?.lowerBound
        XCTAssertNotNil(p1)
        XCTAssertNotNil(p2)
        if let a = p1, let b = p2 {
            XCTAssertTrue(a < b, "Expected CELIA before ORLANDO in markdown")
        }
    }
    func testSceneScriptMissingScene() async throws {
        let sample = """
        As You Like It
        **** ACT I ****
        **** SCENE I. Orchard of Oliver's house. ****
        ADAM
        Yonder comes my master, your brother.
        """

        let dir = NSTemporaryDirectory()
        let path = (dir as NSString).appendingPathComponent("test-play.fountain")
        try sample.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        setenv("FOUNTAIN_SOURCE_PATH", path, 1)
        let handler = SpeechAtlasHandlers(store: FountainStoreClient(client: EmbeddedFountainStoreClient()))
        let bad = Components.Schemas.SceneScriptRequest(
            act: "II",
            scene: "I",
            layout: .readable,
            format: .json,
            group_consecutive: true
        )
        let out = try await handler.speechesScript(.init(body: .json(bad)))
        guard case let .badRequest(err) = out, case let .json(e) = err.body else {
            return XCTFail("Expected 400 JSON error")
        }
        XCTAssertTrue(e.error.contains("Scene not found"))
    }
}
