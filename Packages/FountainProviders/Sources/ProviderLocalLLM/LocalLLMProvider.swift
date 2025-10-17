import Foundation
import FountainAICore
import ProviderOpenAI

/// Convenience wrapper for local OpenAI-compatible runtimes (Ollama, LocalAgent, vLLM).
public struct LocalLLMProvider {
    public static func make(endpoint: URL = URL(string: "http://127.0.0.1:11434/v1/chat/completions")!) -> any CoreChatStreaming {
        OpenAICompatibleChatProvider(apiKey: nil, endpoint: endpoint)
    }
}

