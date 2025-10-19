import XCTest
import FountainStoreClient
import FountainAIKit
@testable import MemChatKit

final class ChatFlowTests: XCTestCase {
    final class MockProvider: ChatStreaming, @unchecked Sendable {
        struct Capture { let request: ChatRequest }
        private var captures: [Capture] = []
        private let q = DispatchQueue(label: "mock.provider")
        let answer: String
        init(answer: String) { self.answer = answer }
        func stream(request: ChatRequest, preferStreaming: Bool) -> AsyncThrowingStream<ChatChunk, Error> {
            q.sync { captures.append(.init(request: request)) }
            let ans = answer
            return AsyncThrowingStream { continuation in
                let response = ChatResponse(answer: ans, provider: "mock", model: "mock-model")
                continuation.yield(.init(text: ans, isFinal: true, response: response))
                continuation.finish()
            }
        }
        func complete(request: ChatRequest) async throws -> ChatResponse {
            q.sync { captures.append(.init(request: request)) }
            return ChatResponse(answer: answer, provider: "mock", model: "mock-model")
        }
        func lastCapture() -> Capture? { q.sync { captures.last } }
    }

    @MainActor
    func testSendPersistsTurnAndInjectsContinuity() async throws {
        // Seed in-memory store with continuity
        let embedded = EmbeddedFountainStoreClient()
        let store = FountainStoreClient(client: embedded)
        let corpus = "memchat-e2e"
        _ = try await store.createCorpus(corpus)
        _ = try await store.addPage(.init(corpusId: corpus, pageId: "continuity:0001", url: "store://continuity/0001", host: "store", title: "Continuity"))
        _ = try await store.addSegment(.init(corpusId: corpus, segmentId: "continuity:0001:note", pageId: "continuity:0001", kind: "continuity", text: "Project focus: test pipeline"))

        let mock = MockProvider(answer: "hello")
        let cfg = MemChatConfiguration(memoryCorpusId: corpus, model: "gpt-4o-mini", openAIAPIKey: "sk-test")
        let controller = MemChatController(config: cfg, store: store, chatClientOverride: mock)
        // Wait until continuity digest is loaded
        var tries = 0
        while controller._testContinuityDigest() == nil && tries < 10 {
            tries += 1
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        controller.newChat()
        controller.send("ping")
        // wait briefly for async stream
        try? await Task.sleep(nanoseconds: 400_000_000)

        // Turns appended
        XCTAssertEqual(controller.turns.last?.answer, "hello")

        // Continuity injected into system prompts (assert via captured request messages)
        guard let req = mock.lastCapture()?.request else { return XCTFail("no capture") }
        let sysJoined = req.messages.filter { $0.role == ChatMessage.Role.system }.map { $0.content }.joined(separator: "\n")
        XCTAssertTrue(sysJoined.localizedCaseInsensitiveContains("ContinuityDigest"))
    }
}
