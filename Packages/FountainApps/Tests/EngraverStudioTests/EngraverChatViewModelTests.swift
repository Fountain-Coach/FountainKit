import XCTest
@testable import EngraverChatCore
import FountainAIAdapters
import LLMGatewayAPI

final class EngraverChatViewModelTests: XCTestCase {
    func testSuccessfulTurnProducesDiagnostics() async throws {
        let response = GatewayChatResponse(
            answer: "Hello world",
            provider: "mock",
            model: "mock-model",
            usage: nil,
            raw: nil,
            functionCall: nil
        )
        let streaming = MockGatewayChatStreaming(
            chunks: [
                GatewayChatChunk(text: "Hello ", isFinal: false, response: nil),
                GatewayChatChunk(text: "world", isFinal: true, response: response)
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
                debugEnabled: true
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
        let response = GatewayChatResponse(
            answer: "",
            provider: nil,
            model: nil,
            usage: nil,
            raw: nil,
            functionCall: nil
        )
        let streaming = MockGatewayChatStreaming(
            chunks: [GatewayChatChunk(text: "pending", isFinal: false, response: nil)],
            finalResponse: response,
            delayPerChunk: 1_000_000_000 // 1s to ensure we cancel first
        )
        let viewModel = await MainActor.run {
            EngraverChatViewModel(
                chatClient: streaming,
                persistenceStore: nil,
                debugEnabled: true
            )
        }

        await MainActor.run {
            viewModel.send(prompt: "Long task", systemPrompts: [])
            viewModel.cancelStreaming()
        }
        try await Task.sleep(nanoseconds: 100_000_000)

        let status = await MainActor.run { (viewModel.state, viewModel.diagnostics) }
        XCTAssertEqual(status.0, .idle)
        XCTAssertTrue(status.1.contains { $0.contains("Cancel requested") })
    }

    func testSessionAutoNamingFromPrompt() async throws {
        let response = GatewayChatResponse(
            answer: "Sure",
            provider: "mock",
            model: "mock-model",
            usage: nil,
            raw: nil,
            functionCall: nil
        )
        let streaming = MockGatewayChatStreaming(
            chunks: [
                GatewayChatChunk(text: "Sure", isFinal: true, response: response)
            ],
            finalResponse: response
        )

        let viewModel = await MainActor.run {
            EngraverChatViewModel(
                chatClient: streaming,
                persistenceStore: nil,
                debugEnabled: false
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
        let response = GatewayChatResponse(
            answer: "Done",
            provider: "mock",
            model: "mock-model",
            usage: nil,
            raw: nil,
            functionCall: nil
        )
        let streaming = MockGatewayChatStreaming(
            chunks: [GatewayChatChunk(text: "Done", isFinal: true, response: response)],
            finalResponse: response
        )

        let viewModel = await MainActor.run {
            EngraverChatViewModel(
                chatClient: streaming,
                persistenceStore: nil,
                debugEnabled: true
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
}

private struct MockGatewayChatStreaming: GatewayChatStreaming {
    let chunks: [GatewayChatChunk]
    let finalResponse: GatewayChatResponse
    let delayPerChunk: UInt64

    init(chunks: [GatewayChatChunk], finalResponse: GatewayChatResponse, delayPerChunk: UInt64 = 10_000_000) {
        self.chunks = chunks
        self.finalResponse = finalResponse
        self.delayPerChunk = delayPerChunk
    }

    func stream(request: ChatRequest, preferStreaming: Bool) -> AsyncThrowingStream<GatewayChatChunk, Error> {
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

    func complete(request: ChatRequest) async throws -> GatewayChatResponse {
        finalResponse
    }
}
