import Foundation
import Combine
import FountainStoreClient
import FountainAIKit
import ProviderOpenAI

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
        store: FountainStoreClient? = nil
    ) {
        self.config = config
        self.chatCorpusId = Self.makeChatCorpusId()

        // Resolve store
        let svc: FountainStoreClient
        if let store { svc = store }
        else if let dir = ProcessInfo.processInfo.environment["FOUNTAINSTORE_DIR"], !dir.isEmpty {
            let url: URL
            if dir.hasPrefix("~") {
                url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true)
            } else { url = URL(fileURLWithPath: dir, isDirectory: true) }
            if let disk = try? DiskFountainStoreClient(rootDirectory: url) {
                svc = FountainStoreClient(client: disk)
            } else {
                svc = FountainStoreClient(client: EmbeddedFountainStoreClient())
            }
        } else {
            svc = FountainStoreClient(client: EmbeddedFountainStoreClient())
        }

        // Resolve provider
        let apiKey = config.openAIAPIKey
        let endpoint = config.openAIEndpoint
            ?? (apiKey == nil ? (config.localCompatibleEndpoint ?? URL(string: "http://127.0.0.1:11434/v1/chat/completions")!)
                              : URL(string: "https://api.openai.com/v1/chat/completions")!)
        let chatClient = OpenAICompatibleChatProvider(apiKey: apiKey, endpoint: endpoint)

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
            directMode: true
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
        let isOpenAI = (apiKey != nil) && ((endpoint.host ?? "").contains("openai.com"))
        self.providerLabel = isOpenAI ? "openai" : "local"
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
        let sys = vm.makeSystemPrompts(base: base)
        vm.send(prompt: text, systemPrompts: sys, preferStreaming: true, corpusOverride: chatCorpusId)
    }

    private func trim(_ s: String, limit: Int = 600) -> String {
        let t = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > limit else { return t }
        return String(t.prefix(limit - 1)) + "…"
    }

    private func latestContinuityPageId() async throws -> String? {
        let q = Query(mode: .prefixScan("pageId", "continuity:"), filters: ["corpusId": config.memoryCorpusId], sort: [(field: "pageId", ascending: false)], limit: 1, offset: 0)
        let resp = try await store.query(corpusId: config.memoryCorpusId, collection: "pages", query: q)
        struct PageDoc: Codable { let pageId: String }
        if let doc = resp.documents.first, let page = try? JSONDecoder().decode(PageDoc.self, from: doc) {
            return page.pageId
        }
        return nil
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

    private static func makeChatCorpusId() -> String {
        let ts = Int(Date().timeIntervalSince1970)
        let suffix = UUID().uuidString.prefix(6)
        return "chat-\(ts)-\(suffix)"
    }
}

// MARK: - Memory helpers and connection test
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

    public enum ConnectionStatus: Equatable { case ok(String), fail(String) }
    public func testConnection() async -> ConnectionStatus {
        let apiKey = config.openAIAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = config.openAIEndpoint ?? config.localCompatibleEndpoint else { return .fail("No provider configured") }
        var modelsURL: URL
        let path = endpoint.path
        if path.contains("/chat/completions") {
            modelsURL = endpoint.deletingLastPathComponent().appendingPathComponent("models")
        } else if path.contains("/v1/") {
            modelsURL = endpoint.deletingLastPathComponent().appendingPathComponent("models")
        } else {
            modelsURL = endpoint.appendingPathComponent("v1/models")
        }
        var req = URLRequest(url: modelsURL)
        req.httpMethod = "GET"
        req.timeoutInterval = 3.0
        if let apiKey, !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return .ok(modelsURL.host ?? "ok")
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return .fail("HTTP \(code) at /v1/models")
        } catch { return .fail(error.localizedDescription) }
    }
}
