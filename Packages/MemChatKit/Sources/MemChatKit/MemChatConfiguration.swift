import Foundation

/// Configuration for MemChatKit.
/// - Provides pluggable settings for the underlying provider, memory corpus,
///   and optional observability/trace integration.
public struct MemChatConfiguration: Sendable, Equatable {
    // Memory & persistence
    public var memoryCorpusId: String
    public var chatCollection: String

    // Provider
    public var model: String
    public var openAIAPIKey: String?
    public var openAIEndpoint: URL?
    public var localCompatibleEndpoint: URL?

    // Observability
    public var gatewayURL: URL?
    public var awarenessURL: URL?
    public var bootstrapURL: URL?

    // UI / Transparency
    public var showSemanticPanel: Bool
    public var showSources: Bool
    public var strictMemoryMode: Bool
    // Semantic Browser defaults
    public var browserDefaultMode: String?

    public init(
        memoryCorpusId: String,
        chatCollection: String = "chat-turns",
        model: String = "gpt-4o-mini",
        openAIAPIKey: String? = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
        openAIEndpoint: URL? = ProcessInfo.processInfo.environment["OPENAI_API_URL"].flatMap(URL.init(string:)),
        localCompatibleEndpoint: URL? = ProcessInfo.processInfo.environment["ENGRAVER_LOCAL_LLM_URL"].flatMap(URL.init(string:)),
        gatewayURL: URL? = ProcessInfo.processInfo.environment["FOUNTAIN_GATEWAY_URL"].flatMap(URL.init(string:)),
        awarenessURL: URL? = ProcessInfo.processInfo.environment["AWARENESS_URL"].flatMap(URL.init(string:)),
        bootstrapURL: URL? = ProcessInfo.processInfo.environment["BOOTSTRAP_URL"].flatMap(URL.init(string:)),
        showSemanticPanel: Bool = true,
        showSources: Bool = false,
        strictMemoryMode: Bool = true,
        browserDefaultMode: String? = ProcessInfo.processInfo.environment["SEMANTIC_BROWSER_MODE"]
    ) {
        self.memoryCorpusId = memoryCorpusId
        self.chatCollection = chatCollection
        self.model = model
        self.openAIAPIKey = openAIAPIKey
        self.openAIEndpoint = openAIEndpoint
        self.localCompatibleEndpoint = localCompatibleEndpoint
        self.gatewayURL = gatewayURL
        self.awarenessURL = awarenessURL
        self.bootstrapURL = bootstrapURL
        self.showSemanticPanel = showSemanticPanel
        self.showSources = showSources
        self.strictMemoryMode = strictMemoryMode
        self.browserDefaultMode = browserDefaultMode
    }
}
