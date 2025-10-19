import Foundation
import Combine
import FountainStoreClient
import FountainAIKit
import ProviderOpenAI
import ProviderGateway

/// Public facade for embedding MemChat in host apps.
/// Wraps EngraverChatViewModel and enforces per-chat corpus isolation while
/// retrieving memory from a selected corpus.
@MainActor
public final class MemChatController: ObservableObject {
    public let config: MemChatConfiguration

    // Expose a subset of EngraverChatViewModel for host apps.
    @Published public private(set) var turns: [EngraverChatTurn] = []
    @Published public private(set) var streamingText: String = ""
    @Published public private(set) var state: EngraverChatState = .idle
    @Published public private(set) var chatCorpusId: String
    @Published public private(set) var providerLabel: String = ""
    @Published public private(set) var lastError: String? = nil

    private let vm: EngraverChatViewModel
    private let store: FountainStoreClient
    private var continuityDigest: String? = nil
    private var cancellables: Set<AnyCancellable> = []

    public init(
        config: MemChatConfiguration,
        store: FountainStoreClient? = nil,
        chatClientOverride: ChatStreaming? = nil
    ) {
        self.config = config
        self.chatCorpusId = Self.makeChatCorpusId()

        // Resolve store: MemChat uses embedded store by default to avoid disk-store crashes.
        // Pass an override only for testing.
        let svc: FountainStoreClient
        if let store { svc = store }
        else {
            svc = FountainStoreClient(client: EmbeddedFountainStoreClient())
        }

        // Resolve chat client: prefer Gateway when configured; else direct OpenAI provider
        let useGateway = (config.gatewayURL != nil) && (chatClientOverride == nil)
        let chatClient: ChatStreaming
        if useGateway, let url = config.gatewayURL {
            let gateway = GatewayProvider.make(baseURL: url) { nil }
            chatClient = gateway
        } else {
            let provider = ProviderResolver.selectProvider(apiKey: config.openAIAPIKey,
                                                           openAIEndpoint: config.openAIEndpoint,
                                                           localEndpoint: config.localCompatibleEndpoint)
            let selectedEndpoint = provider?.endpoint ?? ProviderResolver.openAIChatURL
            let defaultClient = OpenAICompatibleChatProvider(apiKey: provider?.usesAPIKey == true ? config.openAIAPIKey : nil,
                                                             endpoint: selectedEndpoint)
            chatClient = chatClientOverride ?? defaultClient
        }

        // Seeding/memory config to point at standard collections
        let browser = SeedingConfiguration.Browser(
            baseURL: URL(string: ProcessInfo.processInfo.environment["SEMANTIC_BROWSER_URL"] ?? "http://127.0.0.1:8003")!,
            apiKey: nil,
            mode: .quick,
            defaultLabels: [],
            pagesCollection: "pages",
            segmentsCollection: "segments",
            entitiesCollection: "entities",
            tablesCollection: "tables",
            storeOverride: nil
        )
        let seeding = SeedingConfiguration(sources: [], browser: browser)

        self.store = svc
        vm = EngraverChatViewModel(
            chatClient: chatClient,
            persistenceStore: svc,
            corpusId: config.memoryCorpusId, // read memory from here
            collection: config.chatCollection,
            availableModels: [config.model],
            defaultModel: config.model,
            debugEnabled: false,
            awarenessBaseURL: config.awarenessURL,
            bootstrapBaseURL: nil,
            bearerToken: nil,
            seedingConfiguration: seeding,
            environmentController: nil,
            semanticSeeder: SemanticBrowserSeeder(),
            gatewayBaseURL: config.gatewayURL ?? URL(string: "http://127.0.0.1:8010")!,
            directMode: !useGateway
        )

        // Bind outputs
        vm.$turns.sink { [weak self] in self?.turns = $0 }.store(in: &cancellables)
        vm.$activeTokens
            .map { $0.joined() }
            .removeDuplicates()
            .debounce(for: .milliseconds(60), scheduler: DispatchQueue.main)
            .sink { [weak self] text in self?.streamingText = text }
            .store(in: &cancellables)
        vm.$state.sink { [weak self] s in self?.state = s }.store(in: &cancellables)
        vm.$lastError.sink { [weak self] e in self?.lastError = e }.store(in: &cancellables)

        Task { await self.loadContinuityDigest() }
        // Provider label
        self.providerLabel = useGateway ? "gateway" : "openai"
    }

    public func newChat() {
        chatCorpusId = Self.makeChatCorpusId()
        vm.startNewSession()
    }

    public func send(_ text: String) {
        var base: [String] = []
        if let digest = continuityDigest, !digest.isEmpty {
            base.append("ContinuityDigest: \(digest)")
        }
        // Lightweight memory retrieval from the selected memory corpus (segments collection)
        Task { [weak self] in
            guard let self else { return }
            let snippets = await self.retrieveMemorySnippets(matching: text, limit: 5)
            var enriched = base
            if !snippets.isEmpty {
                let list = snippets.map { "• \($0)" }.joined(separator: "\n")
                enriched.append("Memory snippets (from corpus \(self.config.memoryCorpusId)):\n\(list)")
            }
            let sys = self.vm.makeSystemPrompts(base: enriched)
            await MainActor.run {
                self.vm.send(prompt: text, systemPrompts: sys, preferStreaming: true, corpusOverride: self.chatCorpusId)
            }
        }
    }

    private func trim(_ s: String, limit: Int = 600) -> String {
        let t = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > limit else { return t }
        return String(t.prefix(limit - 1)) + "…"
    }

    private func latestContinuityPageId() async throws -> String? {
        // Fallback to simple filters-only query and compute prefix match client-side
        let q = Query(filters: ["corpusId": config.memoryCorpusId], limit: 1000, offset: 0)
        let resp = try await store.query(corpusId: config.memoryCorpusId, collection: "pages", query: q)
        struct PageDoc: Codable { let pageId: String }
        let pages: [PageDoc] = resp.documents.compactMap { try? JSONDecoder().decode(PageDoc.self, from: $0) }
        let continuity = pages.map { $0.pageId }.filter { $0.hasPrefix("continuity:") }.sorted(by: >)
        return continuity.first
    }

    private func loadContinuityDigest() async {
        do {
            guard let pageId = try await latestContinuityPageId() else { return }
            let q = Query(filters: ["corpusId": config.memoryCorpusId, "pageId": pageId], limit: 5, offset: 0)
            let resp = try await store.query(corpusId: config.memoryCorpusId, collection: "segments", query: q)
            // Use the first segment's text as digest (trimmed)
            struct SegmentDoc: Codable { let text: String }
            if let data = resp.documents.first, let seg = try? JSONDecoder().decode(SegmentDoc.self, from: data) {
                await MainActor.run { self.continuityDigest = trim(seg.text, limit: 600) }
            }
        } catch {
            // ignore
        }
    }

    // MARK: - Memory retrieval
    private func retrieveMemorySnippets(matching query: String, limit: Int = 5) async -> [String] {
        do {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let needle = trimmed.split(separator: " ").prefix(8).joined(separator: " ")
            var q = Query(filters: ["corpusId": config.memoryCorpusId], limit: limit * 3, offset: 0)
            if !needle.isEmpty { q.text = String(needle) }
            // Prefer most recently updated segments if available
            q.sort = [("updatedAt", false)]
            let resp = try await store.query(corpusId: config.memoryCorpusId, collection: "segments", query: q)
            struct SegmentDoc: Codable { let text: String }
            let texts: [String] = resp.documents.compactMap { data in
                (try? JSONDecoder().decode(SegmentDoc.self, from: data))?.text
            }
            let unique = Array(Set(texts)).prefix(limit)
            return unique.map { trim($0, limit: 320) }
        } catch {
            return []
        }
    }

    // MARK: - Test helpers (internal)
    func _testContinuityDigest() -> String? { continuityDigest }

    private static func makeChatCorpusId() -> String {
        let ts = Int(Date().timeIntervalSince1970)
        let suffix = UUID().uuidString.prefix(6)
        return "chat-\(ts)-\(suffix)"
    }
}

// MARK: - Memory helpers and connection test
@MainActor public protocol HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}
extension URLSession: HTTPClient {}

extension MemChatController {
    public struct PageItem: Identifiable, Sendable, Hashable, Equatable { public let id: String; public let title: String }

    public func listMemoryPages(limit: Int = 100) async -> [PageItem] {
        do {
            let q = Query(filters: ["corpusId": config.memoryCorpusId], limit: limit, offset: 0)
            let resp = try await store.query(corpusId: config.memoryCorpusId, collection: "pages", query: q)
            struct PageDoc: Codable { let pageId: String; let title: String }
            return resp.documents.compactMap { data in
                (try? JSONDecoder().decode(PageDoc.self, from: data)).map { PageItem(id: $0.pageId, title: $0.title) }
            }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        } catch { return [] }
    }

    public func fetchPageText(pageId: String) async -> String? {
        do {
            let q = Query(filters: ["corpusId": config.memoryCorpusId, "pageId": pageId], limit: 50, offset: 0)
            let resp = try await store.query(corpusId: config.memoryCorpusId, collection: "segments", query: q)
            struct Segment: Codable { let text: String }
            if let first = resp.documents.first, let seg = try? JSONDecoder().decode(Segment.self, from: first) { return seg.text }
            return nil
        } catch { return nil }
    }

    public func loadPlanText() async -> String? { await fetchPageText(pageId: "plan:memchat-features") }

    public enum ConnectionStatus: Equatable, Sendable { case ok(String), fail(String) }
    public func testConnection() async -> ConnectionStatus {
        if let gw = config.gatewayURL {
            var req = URLRequest(url: gw.appending(path: "/metrics"))
            req.httpMethod = "GET"; req.timeoutInterval = 3.0
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) { return .ok("gateway") }
                return .fail("Gateway HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)")
            } catch { return .fail(error.localizedDescription) }
        }
        let provider = ProviderResolver.selectProvider(apiKey: config.openAIAPIKey,
                                                       openAIEndpoint: config.openAIEndpoint,
                                                       localEndpoint: config.localCompatibleEndpoint)
        guard let provider else { return .fail("No provider configured") }
        let apiKey = provider.usesAPIKey ? (config.openAIAPIKey ?? "") : nil
        return await ConnectionTester.test(apiKey: apiKey, endpoint: provider.endpoint)
    }

    /// Performs a live chat roundtrip against OpenAI and returns a short status.
    /// Uses a deterministic prompt and non-streaming call; does not mutate chat state.
    public func testLiveChatRoundtrip() async -> ConnectionStatus {
        let req = ChatRequest(model: config.model, messages: [.init(role: .user, content: "Respond with the single word: ok")])
        if let gw = config.gatewayURL {
            let client = GatewayProvider.make(baseURL: gw) { nil }
            do {
                let resp = try await client.complete(request: req)
                let preview = resp.answer.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !preview.isEmpty else { return .fail("Empty reply from gateway") }
                return .ok(preview)
            } catch { return .fail(String(describing: error)) }
        } else {
            guard let selection = ProviderResolver.selectProvider(apiKey: config.openAIAPIKey,
                                                                  openAIEndpoint: config.openAIEndpoint,
                                                                  localEndpoint: nil) else {
                return .fail("OPENAI_API_KEY not configured")
            }
            let client = OpenAICompatibleChatProvider(apiKey: config.openAIAPIKey, endpoint: selection.endpoint)
            do {
                let resp = try await client.complete(request: req)
                let preview = resp.answer.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !preview.isEmpty else { return .fail("Empty reply from OpenAI") }
                return .ok(preview)
            } catch { return .fail(String(describing: error)) }
        }
    }
}
