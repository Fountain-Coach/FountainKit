import Foundation
import Combine
import FountainAIAdapters
import FountainStoreClient
import LLMGatewayAPI
import ApiClientsCore
import os

/// Current lifecycle state of the chat stream.
public enum EngraverChatState: Equatable, Sendable {
    case idle
    case streaming
    case failed(String)
}

/// Represents a single user ↔ assistant exchange rendered in the Studio.
public struct EngraverChatTurn: Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let prompt: String
    public let answer: String
    public let provider: String?
    public let model: String?
    public let tokens: [String]
    public let response: GatewayChatResponse

    public init(id: UUID,
                createdAt: Date,
                prompt: String,
                answer: String,
                provider: String?,
                model: String?,
                tokens: [String],
                response: GatewayChatResponse) {
        self.id = id
        self.createdAt = createdAt
        self.prompt = prompt
        self.answer = answer
        self.provider = provider
        self.model = model
        self.tokens = tokens
        self.response = response
    }
}

/// Persistent representation of a chat turn stored inside FountainStore.
private struct EngraverChatRecord: Codable, Sendable {
    struct HistoryMessage: Codable, Sendable {
        let role: String
        let content: String
    }

    let recordId: String
    let corpusId: String
    let createdAt: Date
    let prompt: String
    let answer: String
    let provider: String?
    let model: String?
    let usage: JSONValue?
    let raw: JSONValue?
    let functionCall: JSONValue?
    let tokens: [String]
    let systemPrompts: [String]
    let history: [HistoryMessage]
}

/// Concrete persistence configuration captured at view-model initialisation.
private struct PersistenceContext: Sendable {
    let store: FountainStoreClient
    let corpusId: String
    let collection: String

    func overridingCorpus(_ override: String?) -> PersistenceContext {
        guard let override, !override.isEmpty else { return self }
        return PersistenceContext(store: store, corpusId: override, collection: collection)
    }
}

/// Chat history entry used for persistence of the full transcript.
private struct ChatHistoryMessage: Codable, Sendable {
    let role: String
    let content: String
}

@MainActor
public final class EngraverChatViewModel: ObservableObject {
    @Published public private(set) var state: EngraverChatState = .idle
    @Published public private(set) var activeTokens: [String] = []
    @Published public private(set) var turns: [EngraverChatTurn] = []
    @Published public private(set) var lastError: String? = nil
    @Published public private(set) var diagnostics: [String] = []
    @Published public var selectedModel: String

    public let availableModels: [String]

    private let chatClient: GatewayChatStreaming
    private let persistenceContext: PersistenceContext?
    private var streamTask: Task<Void, Never>? = nil
    private let idGenerator: @Sendable () -> UUID
    private let dateProvider: @Sendable () -> Date
    private let debugEnabled: Bool
    private let logger: Logger

    public init(
        chatClient: GatewayChatStreaming,
        persistenceStore: FountainStoreClient? = nil,
        corpusId: String = "engraver-space",
        collection: String = "chat-turns",
        availableModels: [String] = ["gpt-4o-mini"],
        defaultModel: String? = nil,
        debugEnabled: Bool = false,
        idGenerator: @escaping @Sendable () -> UUID = { UUID() },
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.chatClient = chatClient
        if let persistenceStore {
            self.persistenceContext = PersistenceContext(store: persistenceStore, corpusId: corpusId, collection: collection)
        } else {
            self.persistenceContext = nil
        }
        self.availableModels = availableModels
        self.selectedModel = defaultModel ?? availableModels.first ?? "gpt-4o-mini"
        self.debugEnabled = debugEnabled
        self.idGenerator = idGenerator
        self.dateProvider = dateProvider
        self.logger = Logger(subsystem: "FountainApps.EngraverStudio", category: "ViewModel")

        emitDiagnostic("EngraverChatViewModel initialised • corpus=\(corpusId) collection=\(collection) debug=\(debugEnabled)")
    }

    deinit {
        streamTask?.cancel()
    }

    /// Starts a new conversation turn. If a stream is already active it gets cancelled.
    public func send(
        prompt rawPrompt: String,
        systemPrompts: [String] = [],
        preferStreaming: Bool = true,
        corpusOverride: String? = nil
    ) {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        cancelStreaming()
        lastError = nil
        state = .streaming
        emitDiagnostic("Starting turn • promptLength=\(prompt.count) • preferStreaming=\(preferStreaming)")

        let runId = idGenerator()
        let timestamp = dateProvider()
        let model = selectedModel
        let historySnapshot = turns
        let historyMessages = makeHistory(from: historySnapshot)
        let requestMessages = makePromptMessages(
            history: historySnapshot,
            prompt: prompt,
            systemPrompts: systemPrompts
        )
        let request = ChatRequest(model: model, messages: requestMessages)
        let persistenceTarget = persistenceContext?.overridingCorpus(corpusOverride)
        let client = chatClient

        streamTask = Task {
            do {
                var collectedTokens: [String] = []
                var aggregatedAnswer = ""
                var finalResponse: GatewayChatResponse?

                for try await chunk in client.stream(request: request, preferStreaming: preferStreaming) {
                    if !chunk.text.isEmpty {
                        collectedTokens.append(chunk.text)
                        aggregatedAnswer += chunk.text
                        await MainActor.run {
                            self.activeTokens = collectedTokens
                        }
                        emitDiagnostic("Received chunk • text=\"\(chunk.text)\" • final=\(chunk.isFinal)")
                    }
                    if chunk.isFinal, let response = chunk.response {
                        finalResponse = response
                    }
                }

                if finalResponse == nil {
                    let fallback = try await client.complete(request: request)
                    finalResponse = fallback
                    if aggregatedAnswer.isEmpty {
                        aggregatedAnswer = fallback.answer
                    }
                    emitDiagnostic("Stream finished without final chunk – used fallback response.")
                }

                guard let response = finalResponse else {
                    await MainActor.run {
                        self.activeTokens.removeAll()
                        self.state = .failed("gateway.chat.missingFinalResponse")
                        self.lastError = "Gateway did not return a final response."
                    }
                    emitDiagnostic("Failed: Gateway returned no final response.")
                    return
                }

                if aggregatedAnswer.isEmpty {
                    aggregatedAnswer = response.answer
                }

                let turn = EngraverChatTurn(
                    id: runId,
                    createdAt: timestamp,
                    prompt: prompt,
                    answer: aggregatedAnswer,
                    provider: response.provider,
                    model: response.model ?? model,
                    tokens: collectedTokens,
                    response: response
                )

                await MainActor.run {
                    self.turns.append(turn)
                    self.activeTokens.removeAll()
                    self.state = .idle
                }
                emitDiagnostic("Turn completed • tokens=\(collectedTokens.count) • answerLength=\(aggregatedAnswer.count)")

                if let persistenceTarget {
                    await persist(
                        turn: turn,
                        context: persistenceTarget,
                        modelName: model,
                        history: historyMessages,
                        systemPrompts: systemPrompts
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.activeTokens.removeAll()
                    self.state = .idle
                }
                emitDiagnostic("Stream cancelled.")
            } catch {
                await MainActor.run {
                    self.activeTokens.removeAll()
                    self.state = .failed(String(describing: error))
                    self.lastError = String(describing: error)
                }
                emitDiagnostic("Stream error: \(error)")
            }
        }
    }

    /// Cancels the currently active stream (if any) and resets the status to idle.
    public func cancelStreaming() {
        streamTask?.cancel()
        streamTask = nil
        activeTokens.removeAll()
        state = .idle
        emitDiagnostic("Cancel requested.")
    }

    private func makePromptMessages(
        history: [EngraverChatTurn],
        prompt: String,
        systemPrompts: [String]
    ) -> [ChatMessage] {
        var messages: [ChatMessage] = systemPrompts.map { ChatMessage(role: "system", content: $0) }
        for turn in history {
            messages.append(ChatMessage(role: "user", content: turn.prompt))
            messages.append(ChatMessage(role: "assistant", content: turn.answer))
        }
        messages.append(ChatMessage(role: "user", content: prompt))
        return messages
    }

    private func makeHistory(from turns: [EngraverChatTurn]) -> [ChatHistoryMessage] {
        var history: [ChatHistoryMessage] = []
        for turn in turns {
            history.append(ChatHistoryMessage(role: "user", content: turn.prompt))
            history.append(ChatHistoryMessage(role: "assistant", content: turn.answer))
        }
        return history
    }

    private func persist(
        turn: EngraverChatTurn,
        context: PersistenceContext,
        modelName: String,
        history: [ChatHistoryMessage],
        systemPrompts: [String]
    ) async {
        await ensureCorpusExists(context: context)

        let fullHistory = history + [
            ChatHistoryMessage(role: "user", content: turn.prompt),
            ChatHistoryMessage(role: "assistant", content: turn.answer)
        ]

        let record = EngraverChatRecord(
            recordId: turn.id.uuidString,
            corpusId: context.corpusId,
            createdAt: turn.createdAt,
            prompt: turn.prompt,
            answer: turn.answer,
            provider: turn.provider,
            model: turn.model ?? modelName,
            usage: turn.response.usage,
            raw: turn.response.raw,
            functionCall: turn.response.functionCall,
            tokens: turn.tokens,
            systemPrompts: systemPrompts,
            history: fullHistory.map { EngraverChatRecord.HistoryMessage(role: $0.role, content: $0.content) }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(record)
            try await context.store.putDoc(
                corpusId: context.corpusId,
                collection: context.collection,
                id: record.recordId,
                body: data
            )
            emitDiagnostic("Persisted turn \(record.recordId) to FountainStore.")
        } catch PersistenceError.notSupported {
            // FountainStore lacks required capability; ignore for now.
            emitDiagnostic("Persistence skipped: FountainStore missing capability.")
        } catch {
            emitDiagnostic("Persistence error: \(error)")
        }
    }

    private func ensureCorpusExists(context: PersistenceContext) async {
        do {
            if let _ = try await context.store.getCorpus(context.corpusId) {
                return
            }
            _ = try await context.store.createCorpus(
                context.corpusId,
                metadata: [
                    "name": "Engraver Space",
                    "kind": "chat",
                    "collection": context.collection
                ]
            )
            emitDiagnostic("Ensured corpus \(context.corpusId) exists.")
        } catch PersistenceError.notSupported {
            // Not supported; we simply skip corpus creation.
            emitDiagnostic("Corpus creation skipped: not supported.")
        } catch {
            // Best-effort: ignore failures but log for diagnostics.
            emitDiagnostic("Corpus ensure error: \(error)")
        }
    }

    private func emitDiagnostic(_ message: String) {
        logger.log("\(message, privacy: .public)")
        guard debugEnabled else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        diagnostics.append("[\(stamp)] \(message)")
        if diagnostics.count > 200 {
            diagnostics.removeFirst(diagnostics.count - 200)
        }
    }
}
