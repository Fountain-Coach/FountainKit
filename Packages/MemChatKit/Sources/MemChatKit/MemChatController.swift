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

    private let vm: EngraverChatViewModel
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
        vm.$activeTokens.sink { [weak self] tokens in self?.streamingText = tokens.joined() }.store(in: &cancellables)
        vm.$state.sink { [weak self] s in self?.state = s }.store(in: &cancellables)
    }

    public func newChat() {
        chatCorpusId = Self.makeChatCorpusId()
        vm.startNewSession()
    }

    public func send(_ text: String) {
        let sys = vm.makeSystemPrompts(base: [])
        vm.send(prompt: text, systemPrompts: sys, preferStreaming: true, corpusOverride: chatCorpusId)
    }

    private static func makeChatCorpusId() -> String {
        let ts = Int(Date().timeIntervalSince1970)
        let suffix = UUID().uuidString.prefix(6)
        return "chat-\(ts)-\(suffix)"
    }
}

