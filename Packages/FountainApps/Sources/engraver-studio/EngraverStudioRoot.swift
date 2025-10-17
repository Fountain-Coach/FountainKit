import Foundation
#if canImport(SwiftUI)
import SwiftUI
import TeatroGUI
import FountainAIAdapters
import FountainAIKit
import FountainDevHarness
import ProviderOpenAI
import ProviderLocalLLM
import ProviderGateway
import EngraverChatCore

@available(macOS 13.0, *)
public struct EngraverStudioRoot: View {
    private let configuration: EngraverStudioConfiguration
    @StateObject private var viewModel: EngraverChatViewModel

    public init(configuration: EngraverStudioConfiguration = EngraverStudioConfiguration()) {
        self.configuration = configuration
        let client: ChatStreaming = {
            switch configuration.provider {
            case "gateway":
                return GatewayProvider.make(baseURL: configuration.gatewayURL, tokenProvider: configuration.tokenProvider())
            case "openai":
                return OpenAICompatibleChatProvider(apiKey: configuration.openAIAPIKey)
            default:
                return LocalLLMProvider.make(endpoint: configuration.localEndpoint)
            }
        }()
        let envController: EnvironmentController? = configuration.bypassGateway ? nil : EnvironmentControllerAdapter(fountainRepoRoot: configuration.fountainRepoRoot)
        _viewModel = StateObject(
            wrappedValue: EngraverChatViewModel(
                chatClient: client,
                persistenceStore: configuration.persistenceStore,
                corpusId: configuration.corpusId,
                collection: configuration.collection,
                availableModels: configuration.availableModels,
                defaultModel: configuration.defaultModel,
                debugEnabled: configuration.debugEnabled,
                awarenessBaseURL: configuration.awarenessBaseURL,
                bootstrapBaseURL: configuration.bootstrapBaseURL,
                bearerToken: configuration.bearerToken,
                seedingConfiguration: Self.mapSeeding(configuration.seedingConfiguration),
                environmentController: envController,
                gatewayBaseURL: configuration.gatewayBaseURL,
                directMode: configuration.bypassGateway
            )
        )
    }

    public var body: some View {
        EngraverStudioView(
            viewModel: viewModel,
            systemPrompts: configuration.systemPrompts,
            directMode: configuration.bypassGateway
        )
    }
}

@available(macOS 13.0, *)
extension EngraverStudioRoot {
    static func mapSeeding(_ cfg: EngraverStudioConfiguration.SeedingConfiguration?) -> SeedingConfiguration? {
        guard let cfg else { return nil }
        let sources = cfg.sources.map { s in
            SeedingConfiguration.Source(name: s.name, url: s.url, corpusId: s.corpusId, labels: s.labels)
        }
        let browser = SeedingConfiguration.Browser(
            baseURL: cfg.browser.baseURL,
            apiKey: cfg.browser.apiKey,
            mode: SeedingConfiguration.Browser.Mode(rawValue: cfg.browser.mode.rawValue) ?? .standard,
            defaultLabels: cfg.browser.defaultLabels,
            pagesCollection: cfg.browser.pagesCollection,
            segmentsCollection: cfg.browser.segmentsCollection,
            entitiesCollection: cfg.browser.entitiesCollection,
            tablesCollection: cfg.browser.tablesCollection,
            storeOverride: cfg.browser.storeOverride.map { .init(url: $0.url, apiKey: $0.apiKey, timeoutMs: $0.timeoutMs) }
        )
        return SeedingConfiguration(sources: sources, browser: browser)
    }
}
#endif
