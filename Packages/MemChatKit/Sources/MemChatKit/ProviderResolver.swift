import Foundation

struct ProviderResolver {
    struct Selection {
        let label: String // "openai" or "local"
        let endpoint: URL
        let usesAPIKey: Bool
    }

    static let openAIChatURL = URL(string: "https://api.openai.com/v1/chat/completions")!

    /// Select OpenAI as the only supported provider.
    /// - Returns nil when no API key is provided.
    static func selectProvider(apiKey: String?, openAIEndpoint: URL?, localEndpoint: URL?) -> Selection? {
        let trimmedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedKey, !trimmedKey.isEmpty else { return nil }
        let url = openAIEndpoint ?? openAIChatURL
        return Selection(label: "openai", endpoint: url, usesAPIKey: true)
    }

    static func modelsURL(for chatEndpoint: URL) -> URL {
        // If path contains /chat/completions, go up one and append models
        let path = chatEndpoint.path
        if path.contains("/chat/completions") {
            let upOne = chatEndpoint.deletingLastPathComponent() // /v1/chat
            let upTwo = upOne.deletingLastPathComponent()        // /v1
            return upTwo.appendingPathComponent("models")
        }
        if path.contains("/v1/") {
            return chatEndpoint.deletingLastPathComponent().appendingPathComponent("models")
        }
        return chatEndpoint.appendingPathComponent("v1/models")
    }
}
