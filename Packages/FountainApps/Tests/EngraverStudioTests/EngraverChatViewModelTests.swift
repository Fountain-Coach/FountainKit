#if !ROBOT_ONLY
import XCTest
@testable import EngraverChatCore
@testable import FountainAIKit
import Foundation
import OpenAPIRuntime

final class EngraverChatViewModelTests: XCTestCase {
    func testSuccessfulTurnProducesDiagnostics() async throws {
        let response = ChatResponse(answer: "Hello world", provider: "mock", model: "mock-model")
        let streaming = MockGatewayChatStreaming(
            chunks: [
                ChatChunk(text: "Hello ", isFinal: false, response: nil),
                ChatChunk(text: "world", isFinal: true, response: response)
            ],
            finalResponse: response
        )

        let viewModel = await MainActor.run {
            EngraverChatViewModel(
                chatClient: streaming,
                persistenceStore: nil,
                corpusId: "test-corpus",
                collection: "chat-turns",
                availableModels: ["mock-model"],
                defaultModel: "mock-model",
                debugEnabled: true,
                gatewayBaseURL: URL(string: "http://127.0.0.1:0")!
            )
        }

        await MainActor.run {
            viewModel.send(prompt: "Say hello", systemPrompts: [])
        }
        try await Task.sleep(nanoseconds: 200_000_000)

        let stats = await MainActor.run { () -> (Int, String?, Bool, EngraverChatState) in
            (viewModel.turns.count,
             viewModel.turns.first?.answer,
             viewModel.diagnostics.isEmpty,
             viewModel.state)
        }

        XCTAssertEqual(stats.0, 1)
        XCTAssertEqual(stats.1, "Hello world")
        XCTAssertFalse(stats.2)
        XCTAssertEqual(stats.3, .idle)
    }

    func testCancellationLeavesModelIdle() async throws {
        let response = ChatResponse(answer: "", provider: nil, model: nil)
        let streaming = MockGatewayChatStreaming(
            chunks: [ChatChunk(text: "pending", isFinal: false, response: nil)],
            finalResponse: response,
            delayPerChunk: 1_000_000_000 // 1s to ensure we cancel first
        )
        let viewModel = await MainActor.run {
            EngraverChatViewModel(
                chatClient: streaming,
                persistenceStore: nil,
                debugEnabled: true,
                gatewayBaseURL: URL(string: "http://127.0.0.1:0")!
            )
        }

        await MainActor.run {
            viewModel.send(prompt: "Long task", systemPrompts: [])
            viewModel.cancelStreaming()
        }
        let status = await MainActor.run { viewModel.diagnostics }
        XCTAssertTrue(status.contains { $0.contains("Cancel requested") })
    }

    func testSessionAutoNamingFromPrompt() async throws {
        let response = ChatResponse(answer: "Sure", provider: "mock", model: "mock-model")
        let streaming = MockGatewayChatStreaming(
            chunks: [
                ChatChunk(text: "Sure", isFinal: true, response: response)
            ],
            finalResponse: response
        )

        let viewModel = await MainActor.run {
            EngraverChatViewModel(
                chatClient: streaming,
                persistenceStore: nil,
                debugEnabled: false,
                gatewayBaseURL: URL(string: "http://127.0.0.1:0")!
            )
        }

        await MainActor.run {
            viewModel.send(prompt: "Plan the expo booth logistics", systemPrompts: [])
        }
        try await Task.sleep(nanoseconds: 200_000_000)

        let sessionName = await MainActor.run { viewModel.sessionName }
        XCTAssertEqual(sessionName, "Plan the expo booth logistics")
    }

    func testStartNewSessionResetsState() async throws {
        let response = ChatResponse(answer: "Done", provider: "mock", model: "mock-model")
        let streaming = MockGatewayChatStreaming(
            chunks: [ChatChunk(text: "Done", isFinal: true, response: response)],
            finalResponse: response
        )

        let viewModel = await MainActor.run {
            EngraverChatViewModel(
                chatClient: streaming,
                persistenceStore: nil,
                debugEnabled: true,
                gatewayBaseURL: URL(string: "http://127.0.0.1:0")!
            )
        }

        await MainActor.run {
            viewModel.send(prompt: "First turn", systemPrompts: [])
        }
        try await Task.sleep(nanoseconds: 200_000_000)

        let previousSessionId = await MainActor.run { viewModel.sessionId }

        await MainActor.run {
            viewModel.startNewSession()
        }

        let snapshot = await MainActor.run { () -> (Int, UUID, String?, [String]) in
            (viewModel.turns.count, viewModel.sessionId, viewModel.sessionName, viewModel.diagnostics)
        }

        XCTAssertEqual(snapshot.0, 0)
        XCTAssertNotEqual(snapshot.1, previousSessionId)
        XCTAssertNil(snapshot.2)
        XCTAssertTrue(snapshot.3.last?.contains("Started new chat session") ?? false)
    }

    func testParseAwarenessEventsProducesSortedTimeline() async throws {
        let snapshot = EngraverChatViewModel.AwarenessAnalyticsSnapshot(
            total: nil,
            events: [
                .init(type: "baseline", id: "b1", ts: 90, content_len: 120, question: nil),
                .init(type: "reflection", id: "r1", ts: 120, content_len: nil, question: "What changed?"),
                .init(type: "drift", id: "d1", ts: 60, content_len: 45, question: nil),
                .init(type: "unknown", id: "u1", ts: nil, content_len: nil, question: nil)
            ]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)
        let container = try JSONDecoder().decode(OpenAPIObjectContainer.self, from: data)

        let result = await MainActor.run {
            EngraverChatViewModel.parseAwarenessEvents(from: container)
        }

        XCTAssertEqual(result.total, 4, "Total should fall back to event count when API omits the field")
        let identifiers = result.events.map { $0.eventId }
        XCTAssertEqual(identifiers, ["r1", "b1", "d1", "u1"], "Events should be sorted by timestamp descending with unknowns last")

        let reflection = result.events.first { $0.eventId == "r1" }
        XCTAssertEqual(reflection?.kind, .reflection)
        XCTAssertEqual(reflection?.details, "What changed?")
    }

    func testNormalizeMetricsTruncatesLongOutput() async {
        let short = await MainActor.run {
            EngraverChatViewModel.normalizeMetrics("metric 1\nmetric 2")
        }
        XCTAssertEqual(short, "metric 1\nmetric 2")

        let payload = String(repeating: "a", count: 6000)
        let normalized = await MainActor.run {
            EngraverChatViewModel.normalizeMetrics(payload)
        }
        XCTAssertTrue(normalized.hasSuffix("\n…metrics truncated…"))
        XCTAssertLessThan(normalized.count, payload.count)
        XCTAssertEqual(String(normalized.prefix(10)), String(repeating: "a", count: 10))
    }

    func testGenerateSeedManifestsCreatesSummary() async throws {
        throw XCTSkip("Semantic Browser seeding response requires full snapshot payload; covered in API conformance tests.")
    }

    private func waitForSeedingCompletion(_ viewModel: EngraverChatViewModel, timeout: TimeInterval = 3.0) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let state = await MainActor.run { viewModel.seedingState }
            if case .running = state {
                try await Task.sleep(nanoseconds: 50_000_000)
                continue
            }
            return
        }
        XCTFail("Timed out waiting for seeding to complete")
    }

}

private struct MockGatewayChatStreaming: ChatStreaming {
    let chunks: [ChatChunk]
    let finalResponse: ChatResponse
    let delayPerChunk: UInt64

    init(chunks: [ChatChunk], finalResponse: ChatResponse, delayPerChunk: UInt64 = 10_000_000) {
        self.chunks = chunks
        self.finalResponse = finalResponse
        self.delayPerChunk = delayPerChunk
    }

    func stream(request: ChatRequest, preferStreaming: Bool) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            let worker = Task {
                for chunk in chunks {
                    if delayPerChunk > 0 {
                        try? await Task.sleep(nanoseconds: delayPerChunk)
                    }
                    if Task.isCancelled {
                        continuation.finish(throwing: CancellationError())
                        return
                    }
                    continuation.yield(chunk)
                }
                if Task.isCancelled {
                    continuation.finish(throwing: CancellationError())
                } else {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                worker.cancel()
            }
        }
    }

    func complete(request: ChatRequest) async throws -> ChatResponse {
        finalResponse
    }
}
#endif // !ROBOT_ONLY
