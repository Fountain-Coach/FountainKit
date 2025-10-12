import XCTest
import FountainStoreClient
@testable import SpeechAtlasService

final class SpeechAtlasHandlersTests: XCTestCase {
    private struct Fixtures {
        let corpusId: String
        let actOnePageId: String
        let actTwoPageId: String
        let romeoFirst: String
        let romeoSecond: String
        let mercutio: String
        let juliet: String
    }

    private func makeHandlers() async throws -> (SpeechAtlasHandlers, Fixtures) {
        let corpusId = "the-four-stars"
        let embedded = EmbeddedFountainStoreClient()
        let store = FountainStoreClient(client: embedded)

        _ = try await store.createCorpus(corpusId)

        let actOnePage = Page(
            corpusId: corpusId,
            pageId: "page-act-i-scene-i",
            url: "https://example.com/act-i-scene-i",
            host: "example.com",
            title: "Act I Scene I"
        )
        let actTwoPage = Page(
            corpusId: corpusId,
            pageId: "page-act-ii-scene-i",
            url: "https://example.com/act-ii-scene-i",
            host: "example.com",
            title: "Act II Scene I"
        )

        for page in [actOnePage, actTwoPage] {
            _ = try await store.addPage(page)
        }

        let segments: [Segment] = [
            .init(corpusId: corpusId, segmentId: "romeo-1", pageId: actOnePage.pageId, kind: "speech", text: "But soft, what light\nthrough yonder window breaks?"),
            .init(corpusId: corpusId, segmentId: "romeo-2", pageId: actOnePage.pageId, kind: "speech", text: "It is the east,\nand Juliet is the sun."),
            .init(corpusId: corpusId, segmentId: "mercutio-1", pageId: actOnePage.pageId, kind: "speech", text: "A plague o' both your houses!"),
            .init(corpusId: corpusId, segmentId: "juliet-1", pageId: actTwoPage.pageId, kind: "speech", text: "Good night, good night!\nParting is such sweet sorrow.")
        ]

        for segment in segments {
            _ = try await store.addSegment(segment)
        }

        let fixtures = Fixtures(
            corpusId: corpusId,
            actOnePageId: actOnePage.pageId,
            actTwoPageId: actTwoPage.pageId,
            romeoFirst: "\(actOnePage.pageId)/romeo-1",
            romeoSecond: "\(actOnePage.pageId)/romeo-2",
            mercutio: "\(actOnePage.pageId)/mercutio-1",
            juliet: "\(actTwoPage.pageId)/juliet-1"
        )

        return (SpeechAtlasHandlers(store: store, corpusId: corpusId), fixtures)
    }

    func testSpeechesListFiltersByActSceneAndSpeaker() async throws {
        let (handlers, fixtures) = try await makeHandlers()
        let request = Components.Schemas.SpeechesListRequest(
            act: "I",
            scene: "I",
            speaker: "Romeo",
            limit: 10,
            offset: 0
        )
        let output = try await handlers.speechesList(.init(body: .json(request)))
        guard case let .ok(ok) = output,
              case let .json(body) = ok.body else {
            return XCTFail("Expected 200 JSON response")
        }
        XCTAssertEqual(body.result.total, 2)
        XCTAssertEqual(body.result.items.count, 2)
        XCTAssertTrue(body.result.items.allSatisfy { $0.act == "I" && $0.scene == "I" })
        XCTAssertTrue(body.result.items.allSatisfy { $0.speaker == "ROMEO" })
        XCTAssertEqual(body.result.items.first?.speech_id, fixtures.romeoFirst)
    }

    func testSpeechesDetailRespectsContextToggle() async throws {
        let (handlers, fixtures) = try await makeHandlers()

        let detailWithContext = try await handlers.speechesDetail(
            .init(body: .json(.init(speech_id: fixtures.romeoSecond)))
        )
        guard case let .ok(withContext) = detailWithContext,
              case let .json(detailBody) = withContext.body else {
            return XCTFail("Expected 200 JSON response with context")
        }

        let detail = detailBody.result
        XCTAssertEqual(detail.speech.speech_id, fixtures.romeoSecond)
        XCTAssertEqual(detail.lines, ["It is the east,", "and Juliet is the sun."])
        let beforeIds = Set(detail.context_before?.map(\.speech_id) ?? [])
        XCTAssertEqual(beforeIds, Set([fixtures.mercutio, fixtures.romeoFirst]))
        XCTAssertNil(detail.context_after)

        let detailWithoutContext = try await handlers.speechesDetail(
            .init(body: .json(.init(speech_id: fixtures.romeoSecond, include_context: false)))
        )
        guard case let .ok(noContext) = detailWithoutContext,
              case let .json(noContextBody) = noContext.body else {
            return XCTFail("Expected 200 JSON response without context")
        }

        XCTAssertNil(noContextBody.result.context_before)
        XCTAssertNil(noContextBody.result.context_after)
    }

    func testSpeechesSummaryAggregatesAcrossActs() async throws {
        let (handlers, fixtures) = try await makeHandlers()
        let request = Components.Schemas.SpeechesSummaryRequest(
            speech_ids: [fixtures.romeoFirst, fixtures.romeoSecond, fixtures.juliet],
            max_speakers: 2
        )
        let output = try await handlers.speechesSummary(.init(body: .json(request)))
        guard case let .ok(ok) = output,
              case let .json(body) = ok.body else {
            return XCTFail("Expected 200 JSON response")
        }

        let summary = body.result
        XCTAssertEqual(summary.speech_count, 3)
        XCTAssertEqual(summary.top_speakers.count, 2)
        XCTAssertEqual(summary.top_speakers.first?.speaker, "ROMEO")
        XCTAssertEqual(summary.top_speakers.first?.speeches, 2)
        XCTAssertEqual(summary.top_speakers.last?.speaker, "JULIET")
        XCTAssertEqual(summary.top_speakers.last?.speeches, 1)

        XCTAssertEqual(summary.acts_covered?.map(\.act).sorted(), ["I", "II"])
        let scenes = summary.scenes_covered?.map { ($0.act, $0.scene) } ?? []
        XCTAssertTrue(scenes.contains(where: { $0.0 == "I" && $0.1 == "I" }))
        XCTAssertTrue(scenes.contains(where: { $0.0 == "II" && $0.1 == "I" }))
    }
}
