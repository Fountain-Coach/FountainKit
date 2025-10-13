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
    public let sessionId: UUID
    public let createdAt: Date
    public let prompt: String
    public let answer: String
    public let provider: String?
    public let model: String?
    public let tokens: [String]
    public let response: GatewayChatResponse

    public init(id: UUID,
                sessionId: UUID,
                createdAt: Date,
                prompt: String,
                answer: String,
                provider: String?,
                model: String?,
                tokens: [String],
                response: GatewayChatResponse) {
        self.id = id
        self.sessionId = sessionId
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
    let sessionId: UUID
    let sessionName: String?
    let sessionStartedAt: Date
    let turnIndex: Int
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
    @Published public private(set) var sessionId: UUID
    @Published public private(set) var sessionName: String? = nil
    @Published public private(set) var sessionStartedAt: Date
    @Published public var selectedModel: String

    public let availableModels: [String]

    private let chatClient: GatewayChatStreaming
    private let persistenceContext: PersistenceContext?
    private var streamTask: Task<Void, Never>? = nil
    private let idGenerator: @Sendable () -> UUID
    private let dateProvider: @Sendable () -> Date
    private let debugEnabled: Bool
    private let logger: Logger
    private static let sessionTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

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
        self.logger = Logger(subsystem: "FountainApps.EngraverChat", category: "ViewModel")

        let initialSessionId = idGenerator()
        self.sessionId = initialSessionId
        self.sessionStartedAt = dateProvider()

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

        ensureSessionName(using: prompt)
        cancelStreaming()
        lastError = nil
        state = .streaming
        emitDiagnostic("Starting turn • promptLength=\(prompt.count) • preferStreaming=\(preferStreaming)")

        let runId = idGenerator()
        let timestamp = dateProvider()
        let model = selectedModel
        let historySnapshot = turns
        let historyMessages = makeHistory(from: historySnapshot)
        let currentSessionId = sessionId
        let currentSessionName = sessionName
        let currentSessionStartedAt = sessionStartedAt
        let turnIndex = historySnapshot.count + 1
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
                    sessionId: currentSessionId,
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
                        systemPrompts: systemPrompts,
                        sessionId: currentSessionId,
                        sessionName: currentSessionName,
                        sessionStartedAt: currentSessionStartedAt,
                        turnIndex: turnIndex
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.activeTokens.removeAll()
                    self.state = .idle
                }
                emitDiagnostic("Stream cancelled.")
            } catch {
                let description = describe(error: error)
                await MainActor.run {
                    self.activeTokens.removeAll()
                    self.state = .failed(description)
                    self.lastError = description
                }
                emitDiagnostic("Stream error: \(description)")
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

    /// Clears the current transcript and starts a fresh session.
    public func startNewSession(named name: String? = nil) {
        cancelStreaming()
        turns.removeAll()
        activeTokens.removeAll()
        lastError = nil
        state = .idle
        diagnostics.removeAll()
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        sessionId = idGenerator()
        sessionStartedAt = dateProvider()
        sessionName = (trimmed?.isEmpty ?? true) ? nil : trimmed
        emitDiagnostic("Started new chat session • id=\(sessionId)")
        if let sessionName {
            emitDiagnostic("Session named \"\(sessionName)\"")
        }
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

    private func ensureSessionName(using prompt: String) {
        guard sessionName == nil else { return }
        let generated = generateSessionName(from: prompt)
        sessionName = generated
        emitDiagnostic("Session named \"\(generated)\"")
    }

    private func generateSessionName(from prompt: String) -> String {
        let singleLine = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let components = singleLine
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .prefix(12)
        var candidate = components.joined(separator: " ")
        if candidate.isEmpty {
            candidate = Self.sessionTitleFormatter.string(from: sessionStartedAt)
        }
        let maxLength = 48
        if candidate.count > maxLength {
            let prefix = candidate.prefix(maxLength - 1)
            return prefix + "…"
        }
        return candidate
    }

    private func persist(
        turn: EngraverChatTurn,
        context: PersistenceContext,
        modelName: String,
        history: [ChatHistoryMessage],
        systemPrompts: [String],
        sessionId: UUID,
        sessionName: String?,
        sessionStartedAt: Date,
        turnIndex: Int
    ) async {
        await ensureCorpusExists(context: context)

        let fullHistory = history + [
            ChatHistoryMessage(role: "user", content: turn.prompt),
            ChatHistoryMessage(role: "assistant", content: turn.answer)
        ]

        let record = EngraverChatRecord(
            recordId: turn.id.uuidString,
            corpusId: context.corpusId,
            sessionId: sessionId,
            sessionName: sessionName,
            sessionStartedAt: sessionStartedAt,
            turnIndex: turnIndex,
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

    private func describe(error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}
