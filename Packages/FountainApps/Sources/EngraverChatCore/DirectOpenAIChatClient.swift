import Foundation
import FountainAIAdapters
import LLMGatewayAPI

/// Minimal direct OpenAI client that conforms to GatewayChatStreaming.
/// Bypasses the local gateway entirely.
public struct DirectOpenAIChatClient: GatewayChatStreaming {
    private let apiKey: String?
    private let endpoint: URL
    private let session: URLSession

    public init(apiKey: String?, endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.session = session
    }

    public func complete(request: ChatRequest) async throws -> GatewayChatResponse {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let body = buildBody(from: request, stream: false)
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            throw GatewayChatError.serverError(statusCode: http.statusCode, message: String(data: data, encoding: .utf8))
        }
        // Very lightweight parse
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return GatewayChatResponse(answer: content, provider: "openai", model: json["model"] as? String, usage: nil, raw: nil, functionCall: nil)
        }
        return GatewayChatResponse(answer: "", provider: "openai", model: nil, usage: nil, raw: nil, functionCall: nil)
    }

    public func stream(request: ChatRequest, preferStreaming: Bool) -> AsyncThrowingStream<GatewayChatChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    if preferStreaming {
                        try await streamSSE(request: request, continuation: continuation)
                    } else {
                        let final = try await complete(request: request)
                        continuation.yield(.init(text: final.answer, isFinal: true, response: final))
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func streamSSE(request: ChatRequest, continuation: AsyncThrowingStream<GatewayChatChunk, Error>.Continuation) async throws {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let body = buildBody(from: request, stream: true)
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, resp) = try await session.bytes(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            throw GatewayChatError.serverError(statusCode: http.statusCode, message: nil)
        }
        var buffer = ""
        func process(_ payload: String) {
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]] else { return }
            if let delta = choices.first?["delta"] as? [String: Any],
               let content = delta["content"] as? String, !content.isEmpty {
                continuation.yield(.init(text: content, isFinal: false, response: nil))
            }
            if let finish = choices.first?["finish_reason"] as? String, finish == "stop" {
                let content = (choices.first?["message"] as? [String: Any])?["content"] as? String ?? ""
                let response = GatewayChatResponse(answer: content, provider: "openai", model: json["model"] as? String, usage: nil, raw: nil, functionCall: nil)
                continuation.yield(.init(text: content, isFinal: true, response: response))
            }
        }
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("data:") {
                let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { break }
                if !buffer.isEmpty { buffer.append("\n") }
                buffer.append(payload)
            } else if trimmed.isEmpty {
                if !buffer.isEmpty { process(buffer); buffer.removeAll(keepingCapacity: true) }
            }
        }
        if !buffer.isEmpty { process(buffer) }
        continuation.finish()
    }
}

// MARK: - LocalAgent controls mapping
private extension DirectOpenAIChatClient {
    func buildBody(from request: ChatRequest, stream: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "model": request.model,
            "messages": request.messages.map { ["role": $0.role, "content": $0.content] },
            "stream": stream
        ]
        // Only attach controls when talking to a LocalAgent-like endpoint (OpenAI would reject unknown keys)
        if apiKey == nil, endpoint.host == "127.0.0.1", endpoint.path.contains("/chat") {
            let env = ProcessInfo.processInfo.environment
            let perf = (env["ENGRAVER_PERF"] ?? "balanced").lowercased()
            // Defaults
            var temperature = 0.8
            var topP = 0.95
            var topK = 40
            var maxTokens = 256
            switch perf {
            case "fast":
                temperature = 0.7; topP = 0.9; topK = 40; maxTokens = 128
            case "quality":
                temperature = 0.9; topP = 0.97; topK = 60; maxTokens = 512
            default: break
            }
            // Allow direct overrides via env
            if let s = env["ENGRAVER_TEMP"], let v = Double(s) { temperature = v }
            if let s = env["ENGRAVER_TOP_P"], let v = Double(s) { topP = v }
            if let s = env["ENGRAVER_TOP_K"], let v = Int(s) { topK = v }
            if let s = env["ENGRAVER_MAX_TOKENS"], let v = Int(s) { maxTokens = v }
            let cores = max(1, ProcessInfo.processInfo.processorCount - 1)
            let threads = Int(env["ENGRAVER_THREADS"] ?? "") ?? cores

            body["temperature"] = temperature
            body["top_p"] = topP
            body["top_k"] = topK
            body["max_tokens"] = maxTokens
            body["threads"] = threads
        }
        return body
    }
}
