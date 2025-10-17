import Foundation
import FountainAICore
import FountainAIAdapters

public struct GatewayProvider {
    public static func make(baseURL: URL, tokenProvider: @escaping GatewayChatClient.TokenProvider) -> any CoreChatStreaming {
        GatewayChatClient(baseURL: baseURL, tokenProvider: tokenProvider)
    }
}

