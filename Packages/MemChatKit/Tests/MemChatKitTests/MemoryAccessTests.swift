import XCTest
import FountainStoreClient
@testable import MemChatKit

final class MemoryAccessTests: XCTestCase {
    @MainActor
    func testListPagesAndFetchText() async throws {
        // Seed in-memory store
        let embedded = EmbeddedFountainStoreClient()
        let store = FountainStoreClient(client: embedded)
        let corpus = "memchat-test"
        _ = try await store.createCorpus(corpus)
        _ = try await store.addPage(.init(corpusId: corpus, pageId: "plan:demo", url: "store://plan/demo", host: "store", title: "Demo Plan"))
        _ = try await store.addSegment(.init(corpusId: corpus, segmentId: "plan:demo:plan", pageId: "plan:demo", kind: "plan", text: "Hello World"))

        let cfg = MemChatConfiguration(memoryCorpusId: corpus, model: "gpt-4o-mini", openAIAPIKey: "sk-xyz")
        let controller = MemChatController(config: cfg, store: store)
        let pages = await controller.listMemoryPages(limit: 10)
        XCTAssertEqual(pages.first?.title, "Demo Plan")
        let text = await controller.fetchPageText(pageId: "plan:demo")
        XCTAssertEqual(text, "Hello World")
    }
}

