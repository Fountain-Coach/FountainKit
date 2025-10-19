import Foundation

struct ProviderResolver {
    struct Selection {
        let label: String // "openai" or "local"
        let endpoint: URL
        let usesAPIKey: Bool
    }

    static let openAIChatURL = URL(string: "https://api.openai.com/v1/chat/completions")!

    static func selectProvider(apiKey: String?, openAIEndpoint: URL?, localEndpoint: URL?) -> Selection? {
        let trimmedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Prefer OpenAI when key exists
        if let trimmedKey, !trimmedKey.isEmpty {
            let url = openAIEndpoint ?? openAIChatURL
            return Selection(label: "openai", endpoint: url, usesAPIKey: true)
        }
        // Otherwise use local if provided
        if let local = localEndpoint {
            return Selection(label: "local", endpoint: local, usesAPIKey: false)
        }
        return nil
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
