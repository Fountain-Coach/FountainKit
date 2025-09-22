import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FountainAICore

public final class OpenAIAdapter: LLMService {
    private let apiKey: String
    private let endpoint: URL
    private let session: URLSession

    public init(apiKey: String,
                endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!,
                session: URLSession = .shared) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.session = session
    }

    public func chat(model: String, messages: [FountainAICore.ChatMessage]) async throws -> String {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role == .system ? "system" : "user", "content": $0.content] }
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "OpenAIAdapter", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: text])
        }

        // Minimal decode for choices[0].message.content
        if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = obj["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }

        // Fallback to raw string
        return String(data: data, encoding: .utf8) ?? ""
    }
}

