import Foundation

struct ComposerAgentClient {
    struct InstrumentContext: Codable {
        var projectName: String
        var screenplay: String
    }

    struct ChatMessagePayload: Codable {
        let role: String
        let text: String
    }

    struct ChatRequest: Codable {
        let messages: [ChatMessagePayload]
        let context: InstrumentContext
    }

    struct ChatResponse: Codable {
        let reply: String
    }

    let endpointURL: URL

    init(endpointURL: URL? = nil) {
        if let endpointURL {
            self.endpointURL = endpointURL
        } else if let env = ProcessInfo.processInfo.environment["COMPOSER_STUDIO_AGENT_URL"],
                  let url = URL(string: env) {
            self.endpointURL = url
        } else {
            self.endpointURL = URL(string: "http://127.0.0.1:8080/agents/composer-studio/chat")!
        }
    }

    func send(messages: [ChatMessage], context: InstrumentContext) async throws -> String {
        let payload = ChatRequest(
            messages: messages.map { message in
                let role: String
                switch message.role {
                case .user: role = "user"
                case .assistant: role = "assistant"
                }
                return ChatMessagePayload(role: role, text: message.text)
            },
            context: context
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(payload)

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                return text
            }
            return "Composer agent returned status \((response as? HTTPURLResponse)?.statusCode ?? -1)."
        }
        if let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data) {
            return decoded.reply
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }
        return "Composer agent responded with an empty body."
    }
}

