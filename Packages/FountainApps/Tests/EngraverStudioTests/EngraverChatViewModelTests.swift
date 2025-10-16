import XCTest
@testable import EngraverChatCore
import FountainAIAdapters
import LLMGatewayAPI
import OpenAPIRuntime

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
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let sourceURL = tempRoot.appendingPathComponent("sample.txt")
        try "Hello, Semantic Browser".write(to: sourceURL, atomically: true, encoding: .utf8)

        let response = GatewayChatResponse(answer: "", provider: nil, model: nil, usage: nil, raw: nil, functionCall: nil)
        let streaming = MockGatewayChatStreaming(chunks: [], finalResponse: response)
        let browser = EngraverStudioConfiguration.SeedingConfiguration.Browser(
            baseURL: URL(string: "http://127.0.0.1:9999")!,
            apiKey: nil,
            mode: .standard,
            defaultLabels: ["sample-play"],
            pagesCollection: nil,
            segmentsCollection: nil,
            entitiesCollection: nil,
            tablesCollection: nil,
            storeOverride: nil
        )
        let source = EngraverStudioConfiguration.SeedingConfiguration.Source(
            name: "Sample",
            url: sourceURL,
            corpusId: "sample-play",
            labels: ["sample-play"]
        )
        let seedingConfig = EngraverStudioConfiguration.SeedingConfiguration(
            sources: [source],
            browser: browser
        )

        let stubSeeder = SemanticBrowserSeeder(requestPerformer: { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let payload = """
            {"index":{"pagesUpserted":1,"segmentsUpserted":5,"entitiesUpserted":0,"tablesUpserted":0}}
            """.data(using: .utf8)!
            return (payload, response)
        })

        let viewModel = await MainActor.run {
            EngraverChatViewModel(
                chatClient: streaming,
                persistenceStore: nil,
                corpusId: "sample-play",
                collection: "chat-turns",
                availableModels: ["mock"],
                defaultModel: "mock",
                debugEnabled: true,
                seedingConfiguration: seedingConfig,
                semanticSeeder: stubSeeder
            )
        }

        await MainActor.run {
            viewModel.generateSeedManifests()
        }

        try await waitForSeedingCompletion(viewModel)

        let runs = await MainActor.run { viewModel.seedRuns }
        XCTAssertEqual(runs.count, 1)
        guard let run = runs.first else {
            return XCTFail("Seed run missing")
        }
        if case .succeeded(_, let segments) = run.state {
            XCTAssertEqual(segments, 5)
        } else {
            XCTFail("Expected run to succeed")
        }
        XCTAssertEqual(run.metrics?.segmentsUpserted, 5)
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
