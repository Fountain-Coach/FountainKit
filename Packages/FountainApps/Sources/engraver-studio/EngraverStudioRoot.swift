import Foundation
#if canImport(SwiftUI)
import SwiftUI
import TeatroGUI
import FountainAIAdapters
import EngraverChatCore

@available(macOS 13.0, *)
public struct EngraverStudioRoot: View {
    private let configuration: EngraverStudioConfiguration
    @StateObject private var viewModel: EngraverChatViewModel

    public init(configuration: EngraverStudioConfiguration = EngraverStudioConfiguration()) {
        self.configuration = configuration
        let client = GatewayChatClient(
            baseURL: configuration.gatewayURL,
            tokenProvider: configuration.tokenProvider()
        )
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
                bootstrapBaseURL: configuration.bootstrapBaseURL
            )
        )
    }

    public var body: some View {
        EngraverStudioView(
            viewModel: viewModel,
            systemPrompts: configuration.systemPrompts
        )
    }
}
#endif
