import Foundation
import Darwin
import Combine
import FountainAICore
import FountainStoreClient
import ApiClientsCore
import AwarenessAPI
import BootstrapAPI
import OpenAPIRuntime
import os
// No direct dependency on DevHarness; environment integration is injected via EnvironmentController.

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
    public let response: CoreChatResponse

    public init(id: UUID,
                sessionId: UUID,
                createdAt: Date,
                prompt: String,
                answer: String,
                provider: String?,
                model: String?,
                tokens: [String],
                response: CoreChatResponse) {
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

/// Summary information for persisted corpus sessions surfaced to UI consumers.
public struct CorpusSessionOverview: Identifiable, Sendable {
    public struct TurnPreview: Identifiable, Sendable {
        public let id: UUID
        public let createdAt: Date
        public let promptPreview: String
        public let answerPreview: String
    }

    public let id: UUID
    public let title: String
    public let corpusId: String
    public let updatedAt: Date
    public let turnCount: Int
    public let lastPromptPreview: String
    public let lastAnswerPreview: String
    public let model: String?
    public let isCurrentSession: Bool
    public let turnPreviews: [TurnPreview]
}

/// Runtime state of the corpus bootstrap pipeline.
public enum BootstrapState: Sendable, Equatable {
    case idle
    case bootstrapping
    case succeeded(Date)
    case failed(message: String, timestamp: Date)
}

/// Lifecycle status for awareness summary refreshes.
public enum AwarenessStatus: Sendable, Equatable {
    case idle(lastUpdated: Date?)
    case refreshing(lastUpdated: Date?)
    case failed(message: String, lastUpdated: Date?)

    public var lastUpdated: Date? {
        switch self {
        case .idle(let date), .refreshing(let date), .failed(_, let date):
            return date
        }
    }

    public var isRefreshing: Bool {
        if case .refreshing = self { return true }
        return false
    }
}

/// Timeline event captured by the Awareness analytics endpoints.
public struct AwarenessEvent: Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case baseline
        case reflection
        case drift
        case patterns
        case unknown
    }

    public let id: UUID
    public let eventId: String
    public let kind: Kind
    public let timestamp: Date?
    public let headline: String
    public let details: String?

    public init(
        id: UUID = UUID(),
        eventId: String,
        kind: Kind,
        timestamp: Date?,
        headline: String,
        details: String? = nil
    ) {
        self.id = id
        self.eventId = eventId
        self.kind = kind
        self.timestamp = timestamp
        self.headline = headline
        self.details = details
    }
}

/// High-level lifecycle state for seeding and ingestion operations.
public enum SeedOperationState: Sendable, Equatable {
    case idle
    case running
    case succeeded(Date, Int)
    case failed(message: String, timestamp: Date)

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

public struct SemanticSeedRun: Identifiable, Sendable {
    public let id: UUID
    public let sourceName: String
    public let sourceURL: URL
    public let corpusId: String
    public let labels: [String]
    public var startedAt: Date
    public var finishedAt: Date?
    public var state: SeedOperationState
    public var metrics: SemanticBrowserSeeder.Metrics?
    public var message: String?

    public init(
        id: UUID = UUID(),
        sourceName: String,
        sourceURL: URL,
        corpusId: String,
        labels: [String],
        startedAt: Date,
        finishedAt: Date? = nil,
        state: SeedOperationState = .running,
        metrics: SemanticBrowserSeeder.Metrics? = nil,
        message: String? = nil
    ) {
        self.id = id
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.corpusId = corpusId
        self.labels = labels
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.state = state
        self.metrics = metrics
        self.message = message
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
    let sessionId: UUID?
    let sessionName: String?
    let sessionStartedAt: Date?
    let turnIndex: Int?
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
    @Published public private(set) var historicalContext: String? = nil
    @Published public private(set) var corpusSessionOverviews: [CorpusSessionOverview] = []
    @Published public private(set) var awarenessSummaryText: String? = nil
    @Published public private(set) var awarenessHistorySummary: String? = nil
    @Published public private(set) var awarenessEvents: [AwarenessEvent] = []
    @Published public private(set) var awarenessEventsTotal: Int = 0
    @Published public private(set) var awarenessSemanticArcJSON: String? = nil
    @Published public private(set) var awarenessMetricsText: String? = nil
    @Published public private(set) var bootstrapState: BootstrapState = .idle
    @Published public private(set) var awarenessStatus: AwarenessStatus = .idle(lastUpdated: nil)
    @Published public private(set) var seedingState: SeedOperationState = .idle
    @Published public private(set) var persistenceResetState: SeedOperationState = .idle
    @Published public private(set) var seedRuns: [SemanticSeedRun] = []
    @Published public private(set) var environmentState: EnvironmentOverallState = .unavailable("Environment manager not configured")
    @Published public private(set) var environmentServices: [EnvironmentServiceStatus] = []
    @Published public private(set) var environmentLogs: [EnvironmentLogEntry] = []
    @Published public var selectedModel: String

    public let availableModels: [String]
    public var corpusIdentifier: String { persistenceContext?.corpusId ?? initialCorpusId }
    public var awarenessEndpoint: URL? { awarenessBaseURL }
    public var bootstrapEndpoint: URL? { bootstrapBaseURL }
    public var canPersist: Bool { persistenceContext != nil }
    public var hasSeedingSupport: Bool { seedingConfiguration != nil }
    public var seedingSources: [SeedingConfiguration.Source] { seedingConfiguration?.sources ?? [] }
    public var seedingBrowserEndpoint: URL? { seedingConfiguration?.browser.baseURL }
    public var seedingBrowserMode: SeedingConfiguration.Browser.Mode? { seedingConfiguration?.browser.mode }
    public var seedingBrowserLabels: [String]? { seedingConfiguration?.browser.defaultLabels }
    public var environmentConfigured: Bool { environmentManager != nil }
    public var environmentIsRunning: Bool {
        if case .running = environmentState {
            return true
        }
        return false
    }
    public var environmentIsBusy: Bool {
        switch environmentState {
        case .starting, .checking, .stopping:
            return true
        default:
            return false
        }
    }

    private let chatClient: CoreChatStreaming
    private let directMode: Bool
    private let gatewayBaseURL: URL
    private let awarenessClient: AwarenessClient?
    private let bootstrapClient: BootstrapClient?
    private let seedingConfiguration: SeedingConfiguration?
    private let environmentController: EnvironmentController?
    private let bearerToken: String?
    private let persistenceContext: PersistenceContext?
    private var streamTask: Task<Void, Never>? = nil
    private var seedingTask: Task<Void, Never>? = nil
    private let idGenerator: @Sendable () -> UUID
    private let dateProvider: @Sendable () -> Date
    private let debugEnabled: Bool
    private let logger: Logger
    private let awarenessBaseURL: URL?
    private let initialCorpusId: String
    private var persistedRecords: [EngraverChatRecord] = []
    private let bootstrapBaseURL: URL?
    private var didBootstrapCorpus: Bool = false
    private var didAutoBootstrapAfterEnvironment: Bool = false
    private var didRequestAutoStartEnvironment: Bool = false
    private var environmentCancellables: Set<AnyCancellable> = []
    private let semanticSeeder: SemanticBrowserSeeder
    private let memoryAugmentationEnabled: Bool = true
    private static let sessionTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    private static let contextTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d 'at' HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: - Gateway traffic control pane
    public struct GatewayRequestEvent: Identifiable, Codable, Sendable {
        public let id: UUID
        public let method: String
        public let path: String
        public let status: Int
        public let durationMs: Int
        public let timestamp: String
        public let client: String?

        enum CodingKeys: String, CodingKey {
            case method, path, status, durationMs, timestamp, client
        }

        public init(id: UUID = UUID(), method: String, path: String, status: Int, durationMs: Int, timestamp: String, client: String?) {
            self.id = id
            self.method = method
            self.path = path
            self.status = status
            self.durationMs = durationMs
            self.timestamp = timestamp
            self.client = client
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.method = try c.decode(String.self, forKey: .method)
            self.path = try c.decode(String.self, forKey: .path)
            self.status = try c.decode(Int.self, forKey: .status)
            self.durationMs = try c.decode(Int.self, forKey: .durationMs)
            self.timestamp = try c.decode(String.self, forKey: .timestamp)
            self.client = try c.decodeIfPresent(String.self, forKey: .client)
            self.id = UUID()
        }
    }
    @Published public private(set) var trafficEvents: [GatewayRequestEvent] = []
    @Published public var trafficAutoRefresh: Bool = false
    private var trafficTask: Task<Void, Never>? = nil
    public func refreshGatewayTraffic() async {
        var url = gatewayBaseURL
        url.append(path: "/admin/recent")
        var req = URLRequest(url: url)
        if let token = bearerToken, !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if data.isEmpty {
                await MainActor.run { self.trafficEvents = [] }
                return
            }
            do {
                let raw = try JSONDecoder().decode([GatewayRequestEvent].self, from: data)
                await MainActor.run { self.trafficEvents = raw }
            } catch {
                if let s = String(data: data, encoding: .utf8), s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await MainActor.run { self.trafficEvents = [] }
                } else {
                    emitDiagnostic("Traffic decode error: \(error)")
                }
            }
        } catch {
            emitDiagnostic("Traffic fetch error: \(error)")
        }
    }

    public func setTrafficAutoRefresh(_ enabled: Bool) {
        trafficAutoRefresh = enabled
        trafficTask?.cancel(); trafficTask = nil
        guard enabled else { return }
        trafficTask = Task { [weak self] in
            while !(Task.isCancelled) {
                await self?.refreshGatewayTraffic()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    public func applyGatewaySettings(restart: Bool) async {
        // Push env so child processes inherit the configuration
        setenv("GATEWAY_DISABLE_RATELIMIT", gatewayRateLimiterEnabled ? "0" : "1", 1)
        setenv("GATEWAY_RATE_LIMIT_PER_MINUTE", String(gatewayRateLimitPerMinute), 1)
        emitDiagnostic("Gateway settings applied • ratelimiter=\(gatewayRateLimiterEnabled ? "on" : "off") limit=\(gatewayRateLimitPerMinute)")
        guard restart, let environmentController else { return }
        await environmentController.stopEnvironment(includeExtras: true, force: true)
        await environmentController.startEnvironment(includeExtras: true)
        // Poll until running to avoid premature requests
        for _ in 0..<30 {
            await environmentController.refreshStatus()
            try? await Task.sleep(nanoseconds: 500_000_000)
            if case .running = environmentState { break }
        }
    }

    // Admin actions
    public func reloadGatewayRoutes() async {
        var url = gatewayBaseURL
        url.append(path: "/admin/routes/reload")
        var req = URLRequest(url: url); req.httpMethod = "POST"
        if let token = bearerToken, !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do { _ = try await URLSession.shared.data(for: req); emitDiagnostic("Gateway routes reloaded.") } catch { emitDiagnostic("Routes reload error: \(error)") }
    }

    // MARK: - Gateway settings (rate limiter)
    @Published public var gatewayRateLimiterEnabled: Bool
    @Published public var gatewayRateLimitPerMinute: Int

    private static func readEnv(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }

    private static func parseBoolEnv(_ value: String?) -> Bool? {
        guard let v = value?.lowercased() else { return nil }
        return (v == "1" || v == "true" || v == "yes") ? true : (v == "0" || v == "false" || v == "no" ? false : nil)
    }

    public init(
        chatClient: CoreChatStreaming,
        persistenceStore: FountainStoreClient? = nil,
        corpusId: String = "engraver-space",
        collection: String = "chat-turns",
        availableModels: [String] = ["gpt-4o-mini"],
        defaultModel: String? = nil,
        debugEnabled: Bool = false,
        awarenessBaseURL: URL? = nil,
        bootstrapBaseURL: URL? = nil,
        bearerToken: String? = nil,
        seedingConfiguration: SeedingConfiguration? = nil,
        environmentController: EnvironmentController? = nil,
        semanticSeeder: SemanticBrowserSeeder = SemanticBrowserSeeder(),
        idGenerator: @escaping @Sendable () -> UUID = { UUID() },
        dateProvider: @escaping @Sendable () -> Date = { Date() },
        gatewayBaseURL: URL,
        directMode: Bool = false
    ) {
        self.chatClient = chatClient
        self.directMode = directMode
        self.gatewayBaseURL = gatewayBaseURL
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
        self.awarenessBaseURL = awarenessBaseURL
        self.initialCorpusId = corpusId
        self.bootstrapBaseURL = bootstrapBaseURL
        self.bearerToken = bearerToken
        self.seedingConfiguration = seedingConfiguration
        self.semanticSeeder = semanticSeeder
        if directMode {
            self.environmentController = nil
            self.environmentState = .unavailable("Environment disabled (direct mode)")
        } else {
            self.environmentController = environmentController
            if environmentController == nil {
                self.environmentState = .unavailable("Environment controller not configured")
            }
        }

        let defaultHeaders = Self.makeDefaultHeaders(bearerToken: bearerToken)
        if let awarenessBaseURL {
            self.awarenessClient = AwarenessClient(baseURL: awarenessBaseURL, defaultHeaders: defaultHeaders)
        } else {
            self.awarenessClient = nil
        }

        if let bootstrapBaseURL {
            var bootstrapHeaders = defaultHeaders
            if bootstrapHeaders["X-API-Key"] == nil, let token = bearerToken, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                bootstrapHeaders["X-API-Key"] = token
            }
            self.bootstrapClient = BootstrapClient(baseURL: bootstrapBaseURL, defaultHeaders: bootstrapHeaders)
        } else {
            self.bootstrapClient = nil
        }

        if awarenessClient != nil {
            if environmentManager == nil {
                self.awarenessStatus = .refreshing(lastUpdated: nil)
            } else {
                self.awarenessStatus = .idle(lastUpdated: nil)
            }
        } else {
            self.awarenessStatus = .idle(lastUpdated: nil)
        }

        if bootstrapClient != nil {
            self.bootstrapState = environmentManager == nil ? .bootstrapping : .idle
        } else {
            self.bootstrapState = .idle
        }

        // Load gateway settings from environment
        let disabledEnv = Self.readEnv("GATEWAY_DISABLE_RATELIMIT")
        let disabled = Self.parseBoolEnv(disabledEnv) ?? false
        self.gatewayRateLimiterEnabled = !disabled
        let rateEnv = Self.readEnv("GATEWAY_RATE_LIMIT_PER_MINUTE")
        self.gatewayRateLimitPerMinute = Int(rateEnv ?? "") ?? 60

        let initialSessionId = idGenerator()
        self.sessionId = initialSessionId
        self.sessionStartedAt = dateProvider()

        emitDiagnostic("EngraverChatViewModel initialised • corpus=\(corpusId) collection=\(collection) debug=\(debugEnabled)")
        if let seedingConfiguration {
            let sourceNames = seedingConfiguration.sources.map(\.name).joined(separator: ", ")
            emitDiagnostic("Semantic seeding enabled • sources=\(seedingConfiguration.sources.count) [\(sourceNames)] • browser=\(seedingConfiguration.browser.baseURL.absoluteString)")
        } else {
            emitDiagnostic("Seeding disabled • configuration unavailable.")
        }

        if let environmentController, !directMode {
            configureEnvironmentController(environmentController)
        }

        if persistenceContext != nil {
            Task { [weak self] in
                await self?.hydrateFromPersistence()
            }
        }
        // When environment manager is unavailable, avoid eager network calls that would error.
        // If a manager is configured, we'll auto-start and then refresh.
    }

    deinit {
        streamTask?.cancel()
        seedingTask?.cancel()
    }

    /// Starts a new conversation turn. If a stream is already active it gets cancelled.
    public func send(
        prompt rawPrompt: String,
        systemPrompts: [String] = [],
        preferStreaming: Bool = true,
        corpusOverride: String? = nil
    ) {
        sendInternal(prompt: rawPrompt,
                     systemPrompts: systemPrompts,
                     preferStreaming: preferStreaming,
                     corpusOverride: corpusOverride,
                     allowRemediation: true)
    }

    private func sendInternal(
        prompt rawPrompt: String,
        systemPrompts: [String],
        preferStreaming: Bool,
        corpusOverride: String?,
        allowRemediation: Bool
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
        // Optional memory augmentation from seeded segments
        var memoryAppendix: [String] = []
        if memoryAugmentationEnabled {
            let snippets = await retrieveMemorySnippets(for: prompt, limit: 5)
            if !snippets.isEmpty {
                let joined = snippets.enumerated().map { idx, s in "\(idx+1). \(s)" }.joined(separator: "\n\n")
                memoryAppendix.append("Relevant knowledge from your corpus (top matches):\n\n\(joined)\n\nUse these facts when answering, and cite them if appropriate.")
                emitDiagnostic("Memory augmentation: \(snippets.count) snippets attached for prompt \(truncateForContext(prompt, limit: 64))")
            }
        }

        let requestMessages = makePromptMessages(
            history: historySnapshot,
            prompt: prompt,
            systemPrompts: systemPrompts + memoryAppendix
        )
        let request = CoreChatRequest(model: model, messages: requestMessages)
        let persistenceTarget = persistenceContext?.overridingCorpus(corpusOverride)
        let client = chatClient

        streamTask = Task {
            do {
                var collectedTokens: [String] = []
                var aggregatedAnswer = ""
                var finalResponse: CoreChatResponse?

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
                        self.state = .failed("chat.missingFinalResponse")
                        self.lastError = "Provider did not return a final response."
                    }
                    emitDiagnostic("Failed: Provider returned no final response.")
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
                // Attempt one-shot auto remediation for common issues
                if allowRemediation, await self.tryAutoRemediateAndRetry(
                    error: error,
                    rawPrompt: rawPrompt,
                    systemPrompts: systemPrompts,
                    preferStreaming: preferStreaming,
                    corpusOverride: corpusOverride
                ) {
                    return
                }
                let description = userFacingError(from: error)
                await MainActor.run {
                    self.activeTokens.removeAll()
                    self.state = .failed(description)
                    self.lastError = description
                }
                emitDiagnostic("Stream error: \(description)")
            }
        }
    }

    // MARK: - Memory Augmentation
    private func retrieveMemorySnippets(for prompt: String, limit: Int = 5) async -> [String] {
        guard let context = persistenceContext, let cfg = seedingConfiguration else { return [] }
        // Prefer configured segments collection; otherwise fall back to a conventional name
        let collection = cfg.browser.segmentsCollection ?? "segments"
        do {
            let q = Query(filters: ["corpusId": context.corpusId], text: prompt, limit: limit)
            let resp = try await context.store.query(corpusId: context.corpusId, collection: collection, query: q)
            var out: [String] = []
            for data in resp.documents {
                if let snippet = extractText(from: data), !snippet.isEmpty {
                    out.append(truncateForContext(snippet, limit: 320))
                }
            }
            return out
        } catch {
            emitDiagnostic("Memory retrieval failed: \(error)")
            return []
        }
    }

    private func extractText(from data: Data) -> String? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Common keys in semantic segments or pages
            let candidates = ["text", "content", "summary", "title", "body"]
            for key in candidates {
                if let s = obj[key] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return s
                }
            }
            // If entities exist, synthesise a brief line
            if let entities = obj["entities"] as? [Any], !entities.isEmpty {
                return "Entities: " + entities.prefix(5).map { String(describing: $0) }.joined(separator: ", ")
            }
        }
        return nil
    }

    private func isCannotConnect(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == -1004 { return true }
        return false
    }

    private func tryAutoRemediateAndRetry(
        error: Error,
        rawPrompt: String,
        systemPrompts: [String],
        preferStreaming: Bool,
        corpusOverride: String?
    ) async -> Bool {
        // Case 1: 429 — disable limiter and retry once (non-streaming to simplify)
        if let pe = error as? ProviderError {
            if case .serverError(let status, _) = pe, status == 429 {
                emitDiagnostic("Auto-remediation: disabling rate limiter and restarting gateway due to 429…")
                self.gatewayRateLimiterEnabled = false
                await applyGatewaySettings(restart: true)
                await MainActor.run {
                    self.sendInternal(prompt: rawPrompt,
                                      systemPrompts: systemPrompts,
                                      preferStreaming: false,
                                      corpusOverride: corpusOverride,
                                      allowRemediation: false)
                }
                return true
            }
        }
        // Case 2: gateway unreachable — ensure environment running and retry once
        if isCannotConnect(error) {
            emitDiagnostic("Auto-remediation: ensuring gateway is running after connection failure…")
            if let environmentManager {
                await environmentManager.startEnvironment(includeExtras: true)
                for _ in 0..<20 { await environmentManager.refreshStatus(); try? await Task.sleep(nanoseconds: 300_000_000); if case .running = environmentState { break } }
            }
            await MainActor.run {
                self.sendInternal(prompt: rawPrompt,
                                  systemPrompts: systemPrompts,
                                  preferStreaming: false,
                                  corpusOverride: corpusOverride,
                                  allowRemediation: false)
            }
            return true
        }
        return false
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
        if persistedRecords.isEmpty && (awarenessSummaryText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            historicalContext = nil
        } else {
            updateHistoricalContext(excluding: sessionId)
        }
        emitDiagnostic("Started new chat session • id=\(sessionId)")
        if let sessionName {
            emitDiagnostic("Session named \"\(sessionName)\"")
        }
    }

    public func refreshAwareness() {
        guard awarenessBaseURL != nil else { return }
        if environmentManager != nil && !environmentIsRunning {
            let last = awarenessStatus.lastUpdated
            awarenessStatus = .failed(message: "Environment not running", lastUpdated: last)
            emitDiagnostic("Skipped awareness refresh: environment offline.")
            return
        }
        let last = awarenessStatus.lastUpdated
        awarenessStatus = .refreshing(lastUpdated: last)
        Task { [weak self] in
            await self?.refreshAwarenessSummary()
        }
    }

    public func rerunBootstrap() {
        guard bootstrapBaseURL != nil else { return }
        if environmentManager != nil && !environmentIsRunning {
            bootstrapState = .failed(message: "Environment not running", timestamp: dateProvider())
            emitDiagnostic("Skipped bootstrap: environment offline.")
            return
        }
        didBootstrapCorpus = false
        bootstrapState = .bootstrapping
        Task { [weak self] in
            await self?.bootstrapCorpusIfNeeded()
        }
    }

    public func generateSeedManifests() {
        runSeedingPipeline()
    }

    public func generateAndUploadSeedManifests() {
        runSeedingPipeline()
    }

    public func purgeLocalStore() {
        guard let context = persistenceContext else {
            let timestamp = dateProvider()
            persistenceResetState = .failed(message: "Persistence is disabled for this workspace.", timestamp: timestamp)
            return
        }

        if persistenceResetState.isRunning {
            return
        }

        persistenceResetState = .running
        emitDiagnostic("Purging FountainStore corpora for development reset.")

        let store = context.store
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let corpora = try await Self.collectAllCorpora(from: store)
                for corpus in corpora {
                    try await store.deleteCorpus(corpus)
                }
                persistedRecords = []
                corpusSessionOverviews = []
                historicalContext = nil
                updateHistoricalContext(excluding: sessionId)
                persistenceResetState = .succeeded(dateProvider(), corpora.count)
                emitDiagnostic("FountainStore purge completed • corpora removed=\(corpora.count)")
            } catch {
                let message = describe(error: error)
                persistenceResetState = .failed(message: message, timestamp: dateProvider())
                emitDiagnostic("FountainStore purge failed: \(message)")
            }
        }
    }

    private static func collectAllCorpora(from store: FountainStoreClient, pageSize: Int = 200) async throws -> [String] {
        var results: [String] = []
        var offset = 0
        while true {
            let page = try await store.listCorpora(limit: pageSize, offset: offset)
            results.append(contentsOf: page.corpora)
            if results.count >= page.total || page.corpora.isEmpty {
                break
            }
            offset += page.corpora.count
        }
        return results
    }

    public func startEnvironment(includeExtras: Bool) {
        guard let environmentManager else { return }
        Task {
            await environmentManager.startEnvironment(includeExtras: includeExtras)
        }
    }

    public func stopEnvironment(includeExtras: Bool, force: Bool) {
        guard let environmentController else { return }
        Task { await environmentController.stopEnvironment(includeExtras: includeExtras, force: force) }
    }

    public func refreshEnvironmentStatus() {
        guard let environmentController else { return }
        Task { await environmentController.refreshStatus() }
    }

    public func clearEnvironmentLogs() {
        environmentController?.clearLogs()
    }

    public func forceKill(pid: String) {
        guard let environmentController else { return }
        Task { await environmentController.forceKillPID(pid) }
    }

    public func restart(service: EnvironmentServiceStatus) {
        guard let environmentController else { return }
        Task { await environmentController.restartService(service) }
    }

    public func fixAllServices() {
        guard let environmentController else { return }
        Task { await environmentController.fixAll() }
    }

    public func openPersistedSession(id: UUID) {
        let records = persistedRecords.filter { sessionIdentifier(for: $0) == id }
        guard !records.isEmpty else {
            emitDiagnostic("Requested persisted session \(id.uuidString) missing from cache.")
            return
        }
        applyPersistedSession(records: records, retainingAllRecords: persistedRecords)
        emitDiagnostic("Loaded persisted session \(id.uuidString)")
    }

    private func makePromptMessages(
        history: [EngraverChatTurn],
        prompt: String,
        systemPrompts: [String]
    ) -> [CoreChatMessage] {
        var messages: [CoreChatMessage] = systemPrompts.map { CoreChatMessage(role: .system, content: $0) }
        for turn in history {
            messages.append(CoreChatMessage(role: .user, content: turn.prompt))
            messages.append(CoreChatMessage(role: .assistant, content: turn.answer))
        }
        messages.append(CoreChatMessage(role: .user, content: prompt))
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
        let generated = generateSessionName(from: prompt, startedAt: sessionStartedAt)
        sessionName = generated
        emitDiagnostic("Session named \"\(generated)\"")
    }

    private func hydrateFromPersistence() async {
        guard let context = persistenceContext else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let response = try await context.store.query(
                corpusId: context.corpusId,
                collection: context.collection,
                query: Query(sort: [("createdAt", false)], limit: 400)
            )
            let records = response.documents.compactMap { data -> EngraverChatRecord? in
                return try? decoder.decode(EngraverChatRecord.self, from: data)
            }
            guard !records.isEmpty else {
                emitDiagnostic("No persisted sessions found to hydrate.")
                return
            }
            applyPersistedSession(records: records, retainingAllRecords: records)
            emitDiagnostic("Hydrated session from persistence • turns=\(turns.count) session=\(sessionName ?? "(untitled)")")
        } catch {
            emitDiagnostic("Hydration error: \(error)")
        }
    }

    private func applyPersistedSession(records: [EngraverChatRecord], retainingAllRecords dataset: [EngraverChatRecord]? = nil) {
        let mergedDataset: [EngraverChatRecord]
        if let dataset {
            mergedDataset = mergeRecords(records, into: dataset)
        } else if persistedRecords.isEmpty {
            mergedDataset = records
        } else {
            mergedDataset = mergeRecords(records, into: persistedRecords)
        }

        let grouped = Dictionary(grouping: mergedDataset, by: sessionIdentifier(for:))
        let requestedSessions = Set(records.map(sessionIdentifier(for:)))

        let targetSessionId: UUID
        let targetRecords: [EngraverChatRecord]
        if requestedSessions.count == 1, let requested = requestedSessions.first, let bucket = grouped[requested] {
            targetSessionId = requested
            targetRecords = bucket.sorted { $0.createdAt < $1.createdAt }
        } else if let latest = grouped.max(by: { lhs, rhs in
            let lhsDate = lhs.value.map { $0.createdAt }.max() ?? .distantPast
            let rhsDate = rhs.value.map { $0.createdAt }.max() ?? .distantPast
            return lhsDate < rhsDate
        }) {
            targetSessionId = latest.key
            targetRecords = latest.value.sorted { $0.createdAt < $1.createdAt }
        } else {
            return
        }

        persistedRecords = mergedDataset

        guard let first = targetRecords.first else { return }

        let resolvedStart = first.sessionStartedAt ?? first.createdAt
        sessionId = targetSessionId
        sessionStartedAt = resolvedStart
        if let name = first.sessionName, !name.isEmpty {
            sessionName = name
        } else {
            sessionName = generateSessionName(from: first.prompt, startedAt: resolvedStart)
        }

        turns = targetRecords.map { record in
            let response = CoreChatResponse(
                answer: record.answer,
                provider: record.provider,
                model: record.model
            )
            return EngraverChatTurn(
                id: UUID(uuidString: record.recordId) ?? UUID(),
                sessionId: targetSessionId,
                createdAt: record.createdAt,
                prompt: record.prompt,
                answer: record.answer,
                provider: record.provider,
                model: record.model,
                tokens: record.tokens,
                response: response
            )
        }

        updateHistoricalContext(excluding: targetSessionId)
    }

    private func cachePersistedRecord(_ record: EngraverChatRecord) {
        if let index = persistedRecords.firstIndex(where: { $0.recordId == record.recordId }) {
            persistedRecords[index] = record
        } else {
            persistedRecords.append(record)
        }
    }

    private func handleEnvironmentStateChange(_ state: EnvironmentOverallState) {
        let previous = environmentState
        environmentState = state

        switch state {
        case .running:
            if !didAutoBootstrapAfterEnvironment {
                didAutoBootstrapAfterEnvironment = true
                if bootstrapClient != nil {
                    bootstrapState = .bootstrapping
                }
                if awarenessClient != nil {
                    let last = awarenessStatus.lastUpdated
                    awarenessStatus = .refreshing(lastUpdated: last)
                }
                Task {
                    await bootstrapCorpusIfNeeded()
                    await refreshAwarenessSummary()
                }
            }
        case .failed(let message):
            didAutoBootstrapAfterEnvironment = false
            if awarenessClient != nil {
                let last = awarenessStatus.lastUpdated
                awarenessStatus = .failed(message: "Environment error: \(message)", lastUpdated: last)
            }
            if bootstrapClient != nil {
                bootstrapState = .idle
            }
        case .idle, .unavailable:
            if case .running = previous {
                if awarenessClient != nil {
                    let last = awarenessStatus.lastUpdated
                    awarenessStatus = .failed(message: "Environment offline", lastUpdated: last)
                }
                if bootstrapClient != nil {
                    bootstrapState = .idle
                }
            }
            didAutoBootstrapAfterEnvironment = false
        default:
            break
        }
    }

    private func configureEnvironmentController(_ controller: EnvironmentController) {
        environmentState = controller.overallState
        environmentServices = controller.services
        environmentLogs = controller.logs
        controller.observeOverallState { [weak self] state in
            self?.handleEnvironmentStateChange(state)
        }.store(in: &environmentCancellables)
        controller.observeServices { [weak self] services in
            self?.environmentServices = services
        }.store(in: &environmentCancellables)
        controller.observeLogs { [weak self] entries in
            self?.environmentLogs = entries
        }.store(in: &environmentCancellables)
        handleEnvironmentStateChange(controller.overallState)
        Task {
            await controller.refreshStatus()
            if !didRequestAutoStartEnvironment {
                switch controller.overallState {
                case .idle, .unavailable, .failed:
                    didRequestAutoStartEnvironment = true
                    await controller.startEnvironment(includeExtras: true)
                default:
                    break
                }
            }
        }
    }

    private func mergeRecords(_ newRecords: [EngraverChatRecord], into existing: [EngraverChatRecord]) -> [EngraverChatRecord] {
        if existing.isEmpty { return newRecords }
        var map = Dictionary(uniqueKeysWithValues: existing.map { ($0.recordId, $0) })
        for record in newRecords {
            map[record.recordId] = record
        }
        return Array(map.values)
    }

    private func sessionIdentifier(for record: EngraverChatRecord) -> UUID {
        if let identifier = record.sessionId {
            return identifier
        }
        return UUID(uuidString: record.recordId) ?? sessionId
    }

    private func generateSessionName(from prompt: String, startedAt: Date? = nil) -> String {
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
            let reference = startedAt ?? sessionStartedAt
            candidate = Self.sessionTitleFormatter.string(from: reference)
        }
        let maxLength = 48
        if candidate.count > maxLength {
            let prefix = candidate.prefix(maxLength - 1)
            return prefix + "…"
        }
        return candidate
    }

    private func updateHistoricalContext(excluding session: UUID) {
        var sections: [String] = []

        if let awarenessSummary = awarenessSummaryText?.trimmingCharacters(in: .whitespacesAndNewlines), !awarenessSummary.isEmpty {
            var awarenessBlock = "Baseline Awareness summary:\n\(awarenessSummary)"
            if let awarenessBaseURL {
                awarenessBlock.append("\n(Service endpoint: \(awarenessBaseURL.absoluteString))")
            }
            sections.append(awarenessBlock)
        }

        if let history = awarenessHistorySummary?.trimmingCharacters(in: .whitespacesAndNewlines), !history.isEmpty {
            sections.append("Awareness history overview:\n\(history)")
        }

        if awarenessEventsTotal > 0 {
            sections.append("Awareness analytics captured \(awarenessEventsTotal) event\(awarenessEventsTotal == 1 ? "" : "s").")
        }

        let overviews = makeSessionOverviews(currentSession: session)
        corpusSessionOverviews = overviews

        let sessionSummaries = overviews
            .filter { !$0.isCurrentSession }
            .map { overview -> String in
                let timestamp = Self.contextTimeFormatter.string(from: overview.updatedAt)
                return "• \(overview.title) (last \(timestamp))\n  ├─ User: \(overview.lastPromptPreview)\n  └─ Assistant: \(overview.lastAnswerPreview)"
            }

        if !sessionSummaries.isEmpty {
            sections.append("Recent Engraver sessions for this corpus:\n\n" + sessionSummaries.joined(separator: "\n"))
        }

        historicalContext = sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    private func makeSessionOverviews(currentSession: UUID) -> [CorpusSessionOverview] {
        guard !persistedRecords.isEmpty else { return [] }

        let grouped = Dictionary(grouping: persistedRecords, by: sessionIdentifier(for:))
        var overviews: [CorpusSessionOverview] = []

        for (sessionId, records) in grouped {
            let sorted = records.sorted { $0.createdAt < $1.createdAt }
            guard let last = sorted.last else { continue }
            let first = sorted.first
            let trimmedName = first?.sessionName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (trimmedName?.isEmpty == false ? trimmedName : nil) ?? "Session \(sessionId.uuidString.prefix(8))"
            let previews = sorted.suffix(3).map { record -> CorpusSessionOverview.TurnPreview in
                CorpusSessionOverview.TurnPreview(
                    id: UUID(uuidString: record.recordId) ?? UUID(),
                    createdAt: record.createdAt,
                    promptPreview: truncateForContext(record.prompt),
                    answerPreview: truncateForContext(record.answer)
                )
            }

            let overview = CorpusSessionOverview(
                id: sessionId,
                title: title,
                corpusId: first?.corpusId ?? initialCorpusId,
                updatedAt: last.createdAt,
                turnCount: sorted.count,
                lastPromptPreview: truncateForContext(last.prompt),
                lastAnswerPreview: truncateForContext(last.answer),
                model: last.model,
                isCurrentSession: sessionId == currentSession,
                turnPreviews: previews
            )
            overviews.append(overview)
        }

        return overviews.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func refreshAwarenessSummary() async {
        guard let awarenessClient else {
            let last = awarenessStatus.lastUpdated
            awarenessStatus = .failed(message: "Awareness client unavailable", lastUpdated: last)
            return
        }
        let corpus = corpusIdentifier
        do {
            async let summaryResponse = awarenessClient.summarizeHistory(corpusID: corpus)
            async let historyResponse = awarenessClient.listHistory(corpusID: corpus)
            async let analyticsResponse = awarenessClient.historyAnalytics(corpusID: corpus)
            async let semanticArcResponse = try? awarenessClient.semanticArc(corpusID: corpus)
            async let metricsResponse = try? awarenessClient.metrics()

            let summary = try await summaryResponse
            let history = try await historyResponse
            let analyticsObject = try await analyticsResponse
            let semanticArc = await semanticArcResponse
            let metrics = await metricsResponse

            let analyticsResult = Self.parseAwarenessEvents(from: analyticsObject)
            let semanticArcJSON = semanticArc.flatMap { prettyJSONString(from: $0) }
            let normalizedMetrics = metrics.map(Self.normalizeMetrics)
            let now = dateProvider()

            await MainActor.run {
                let trimmedSummary = summary.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                awarenessSummaryText = trimmedSummary.isEmpty ? nil : trimmedSummary

                let trimmedHistory = history.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                awarenessHistorySummary = trimmedHistory.isEmpty ? nil : trimmedHistory

                awarenessEvents = analyticsResult.events
                awarenessEventsTotal = analyticsResult.total
                awarenessSemanticArcJSON = semanticArcJSON
                awarenessMetricsText = normalizedMetrics
                awarenessStatus = .idle(lastUpdated: now)
                updateHistoricalContext(excluding: sessionId)
            }
        } catch {
            emitDiagnostic("Awareness summary error: \(error)")
            let last = awarenessStatus.lastUpdated
            await MainActor.run {
                awarenessStatus = .failed(message: String(describing: error), lastUpdated: last)
            }
        }
    }

private func bootstrapCorpusIfNeeded() async {
    guard let bootstrapClient else {
        return
    }
    if didBootstrapCorpus {
        let timestamp = dateProvider()
        bootstrapState = .succeeded(timestamp)
        return
    }
    bootstrapState = .bootstrapping
    let corpus = corpusIdentifier
    do {
        let response = try await bootstrapClient.initializeCorpus(BootstrapAPI.Components.Schemas.InitIn(corpusId: corpus))
        emitDiagnostic("Bootstrap initialized corpus: \(response.message)")
        didBootstrapCorpus = true
        let timestamp = dateProvider()
        bootstrapState = .succeeded(timestamp)
        await MainActor.run {
            awarenessStatus = .refreshing(lastUpdated: awarenessStatus.lastUpdated)
        }
        await refreshAwarenessSummary()
    } catch let error as BootstrapClient.BootstrapClientError {
        switch error {
        case .unexpectedStatus(let code) where code == 409:
            emitDiagnostic("Bootstrap corpus already initialized (409).")
            didBootstrapCorpus = true
            let timestamp = dateProvider()
            bootstrapState = .succeeded(timestamp)
        case .validationError(let validation):
            emitDiagnostic("Bootstrap validation error: \(validation)")
            let timestamp = dateProvider()
            bootstrapState = .failed(message: "Validation error: \(validation)", timestamp: timestamp)
        default:
            emitDiagnostic("Bootstrap error: \(error)")
            let timestamp = dateProvider()
            bootstrapState = .failed(message: String(describing: error), timestamp: timestamp)
        }
    } catch {
        emitDiagnostic("Bootstrap error: \(error)")
        let timestamp = dateProvider()
        bootstrapState = .failed(message: String(describing: error), timestamp: timestamp)
    }
}

    private func runSeedingPipeline() {
        guard let configuration = seedingConfiguration else {
            let timestamp = dateProvider()
            seedingState = .failed(message: "Seeding is not configured for this workspace.", timestamp: timestamp)
            return
        }

        let sources = configuration.sources
        if sources.isEmpty {
            let timestamp = dateProvider()
            seedingState = .failed(message: "No semantic sources configured.", timestamp: timestamp)
            return
        }

        seedingTask?.cancel()
        seedingState = .running

        let seeder = semanticSeeder
        let browser = configuration.browser

        let initialRuns = sources.map { source -> SemanticSeedRun in
            SemanticSeedRun(
                sourceName: source.name,
                sourceURL: source.url,
                corpusId: source.corpusId,
                labels: source.labels,
                startedAt: dateProvider(),
                finishedAt: nil,
                state: .running,
                metrics: nil,
                message: nil
            )
        }
        seedRuns = initialRuns
        emitDiagnostic("Semantic seeding pipeline started • sources=\(sources.count)")

        seedingTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var totalSegments = 0
            var completed = 0

            for (index, source) in sources.enumerated() {
                await MainActor.run {
                    var run = self.seedRuns[index]
                    run.startedAt = self.dateProvider()
                    run.finishedAt = nil
                    run.metrics = nil
                    run.message = nil
                    run.state = .running
                    self.seedRuns[index] = run
                }

                do {
                    let metrics = try await seeder.run(
                        source: source,
                        browser: browser,
                        emitDiagnostic: { message in
                            Task { @MainActor in
                                self.emitDiagnostic(message)
                            }
                        }
                    )
                    totalSegments += metrics.segmentsUpserted
                    completed += 1
                    await MainActor.run {
                        let finished = self.dateProvider()
                        var run = self.seedRuns[index]
                        run.finishedAt = finished
                        run.metrics = metrics
                        run.state = .succeeded(finished, metrics.segmentsUpserted)
                        run.message = nil
                        self.seedRuns[index] = run
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        let finished = self.dateProvider()
                        var run = self.seedRuns[index]
                        run.finishedAt = finished
                        run.state = .idle
                        run.message = "Cancelled"
                        self.seedRuns[index] = run
                        self.seedingState = .idle
                    }
                    return
                } catch {
                    let message = self.describe(error: error)
                    await MainActor.run {
                        let finished = self.dateProvider()
                        var run = self.seedRuns[index]
                        run.finishedAt = finished
                        run.state = .failed(message: message, timestamp: finished)
                        run.message = message
                        self.seedRuns[index] = run
                    }
                }
            }

            await MainActor.run {
                let finished = self.dateProvider()
                if completed == sources.count {
                    self.seedingState = .succeeded(finished, totalSegments)
                    self.emitDiagnostic("Semantic seeding completed • sources=\(sources.count) segments=\(totalSegments)")
                } else if completed == 0 {
                    self.seedingState = .failed(message: "Semantic seeding failed for all sources.", timestamp: finished)
                } else {
                    let failures = sources.count - completed
                    self.seedingState = .failed(message: "Semantic seeding completed with \(failures) failure\(failures == 1 ? "" : "s").", timestamp: finished)
                }
            }
        }
    }

    static func parseAwarenessEvents(from object: OpenAPIObjectContainer) -> (total: Int, events: [AwarenessEvent]) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(object) else { return (0, []) }
        guard let decoded = try? JSONDecoder().decode(AwarenessAnalyticsSnapshot.self, from: data) else {
            return (0, [])
        }
        let events = decoded.events?.map { event -> AwarenessEvent in
            let kind = AwarenessEvent.Kind(rawValue: event.type ?? "") ?? .unknown
            let eventId = event.id ?? UUID().uuidString
            let timestamp = event.ts.map { Date(timeIntervalSince1970: $0) }
            let headline: String
            switch kind {
            case .baseline:
                if let length = event.content_len {
                    headline = "Baseline \(eventId) (\(length) chars)"
                } else {
                    headline = "Baseline \(eventId)"
                }
            case .reflection:
                headline = "Reflection \(eventId)"
            case .drift:
                if let length = event.content_len {
                    headline = "Drift analysis \(eventId) (\(length) chars)"
                } else {
                    headline = "Drift analysis \(eventId)"
                }
            case .patterns:
                if let length = event.content_len {
                    headline = "Patterns \(eventId) (\(length) chars)"
                } else {
                    headline = "Patterns \(eventId)"
                }
            case .unknown:
                headline = eventId
            }
            let details: String?
            if let question = event.question, !question.isEmpty {
                details = question
            } else if let length = event.content_len {
                details = "\(length) characters"
            } else {
                details = nil
            }
            return AwarenessEvent(
                eventId: eventId,
                kind: kind,
                timestamp: timestamp,
                headline: headline,
                details: details
            )
        } ?? []
        let total = decoded.total ?? events.count
        let sorted = events.sorted { lhs, rhs in
            switch (lhs.timestamp, rhs.timestamp) {
            case let (l?, r?): return l > r
            case (nil, _?): return false
            case (_?, nil): return true
            default: return lhs.headline < rhs.headline
            }
        }
        return (total, sorted)
    }

    private func prettyJSONString<T: Encodable>(from value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func normalizeMetrics(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxCharacters = 5_000
        guard trimmed.count > maxCharacters else { return trimmed }
        let prefix = trimmed.prefix(maxCharacters)
        return String(prefix) + "\n…metrics truncated…"
    }

    private static func makeDefaultHeaders(bearerToken: String?) -> [String: String] {
        guard let token = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            return [:]
        }
        return ["Authorization": "Bearer \(token)"]
    }

    struct AwarenessAnalyticsSnapshot: Codable {
        struct Event: Codable {
            let type: String?
            let id: String?
            let ts: Double?
            let content_len: Int?
            let question: String?
        }

        let total: Int?
        let events: [Event]?
    }

    private func truncateForContext(_ text: String, limit: Int = 160) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard singleLine.count > limit else { return singleLine }
        return String(singleLine.prefix(limit - 1)) + "…"
    }

    public func makeSystemPrompts(base: [String]) -> [String] {
        var prompts = base
        if let context = historicalContext, !context.isEmpty {
            prompts.append("Historical context from your prior sessions and services:\n\n\(context)\n\nUse this knowledge when assisting the user, while prioritising their latest instructions.")
        }
        if awarenessBaseURL != nil {
            let endpointDescription = awarenessBaseURL?.absoluteString ?? "http://127.0.0.1:8001"
            prompts.append("You have access to the Baseline Awareness service at \(endpointDescription). It provides baselines, drift events, narrative patterns, and reflections for this corpus. Reference it when discussing long-term context.")
        }
        if bootstrapBaseURL != nil {
            let endpoint = bootstrapBaseURL?.absoluteString ?? "http://127.0.0.1:8002"
            prompts.append("Bootstrap service is available at \(endpoint). Use it to initialize corpora, seed default GPT roles, and register new baselines when needed.")
        }
        return prompts
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
            usage: nil,
            raw: nil,
            functionCall: nil,
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
            cachePersistedRecord(record)
            updateHistoricalContext(excluding: sessionId)
            await refreshAwarenessSummary()
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

    private func userFacingError(from error: Error) -> String {
        // Map common provider/gateway errors to friendly messages with hints.
        if let pe = error as? ProviderError {
            switch pe {
            case .serverError(let status, let message):
                if status == 429 {
                    let src = directMode ? "Provider" : "Gateway"
                    return "\(src) rate limited (429). Reduce request rate or increase limits.\(message.map { "\n\nDetails: \($0)" } ?? "")"
                } else if status == 401 || status == 403 {
                    let src = directMode ? "Provider" : "Gateway"
                    return "\(src) authentication failed (\(status)). Ensure API key is set.\(message.map { "\n\nDetails: \($0)" } ?? "")"
                }
                let src = directMode ? "Provider" : "Gateway"
                return "\(src) returned status \(status).\(message.map { "\n\nDetails: \($0)" } ?? "")"
            case .invalidResponse:
                let src = directMode ? "Provider" : "Gateway"
                return "\(src) did not return a valid HTTP response. Check connectivity."
            case .networkError(let msg):
                let src = directMode ? "Provider" : "Gateway"
                return "\(src) network error: \(msg)"
            }
        }
        return describe(error: error)
    }
}
