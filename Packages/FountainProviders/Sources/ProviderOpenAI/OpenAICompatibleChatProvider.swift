import Foundation
import FountainAICore

/// Minimal OpenAI-compatible chat provider implementing CoreChatStreaming.
/// Works with hosted OpenAI (when apiKey is set) and OpenAI-compatible local runtimes (when apiKey is nil).
public struct OpenAICompatibleChatProvider: CoreChatStreaming {
    private let apiKey: String?
    private let endpoint: URL
    private let session: URLSession

    public init(apiKey: String?, endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.session = session
    }

    public func complete(request: CoreChatRequest) async throws -> CoreChatResponse {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let body = buildBody(from: request, stream: false)
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw ProviderError.invalidResponse }
            guard (200...299).contains(http.statusCode) else {
                throw ProviderError.serverError(statusCode: http.statusCode, message: String(data: data, encoding: .utf8))
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]] {
                if let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    return CoreChatResponse(answer: content, provider: apiKey == nil ? "local" : "openai", model: json["model"] as? String)
                }
                if let text = choices.first?["text"] as? String, !text.isEmpty {
                    return CoreChatResponse(answer: text, provider: apiKey == nil ? "local" : "openai", model: json["model"] as? String)
                }
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let answer = json["answer"] as? String {
                return CoreChatResponse(answer: answer, provider: "local", model: nil)
            }
        } catch {
            throw map(error)
        }
        throw ProviderError.invalidResponse
    }

    public func stream(request: CoreChatRequest, preferStreaming: Bool) -> AsyncThrowingStream<CoreChatChunk, Error> {
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
                    continuation.finish(throwing: map(error))
                }
            }
        }
    }

    private func streamSSE(request: CoreChatRequest, continuation: AsyncThrowingStream<CoreChatChunk, Error>.Continuation) async throws {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let body = buildBody(from: request, stream: true)
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, resp) = try await session.bytes(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ProviderError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.serverError(statusCode: http.statusCode, message: nil)
        }
        var buffer = ""
        func process(_ payload: String) {
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            if let choices = json["choices"] as? [[String: Any]] {
                if let delta = choices.first?["delta"] as? [String: Any],
                   let content = delta["content"] as? String, !content.isEmpty {
                    continuation.yield(.init(text: content, isFinal: false, response: nil))
                }
                if let finish = choices.first?["finish_reason"] as? String, finish == "stop" {
                    let content = (choices.first?["message"] as? [String: Any])?["content"] as? String ?? ""
                    let response = CoreChatResponse(answer: content, provider: apiKey == nil ? "local" : "openai", model: json["model"] as? String)
                    continuation.yield(.init(text: content, isFinal: true, response: response))
                }
                return
            }
            // LocalAgent SSE
            if let delta = json["delta"] as? String, !delta.isEmpty {
                continuation.yield(.init(text: delta, isFinal: false, response: nil))
                return
            }
            if let answer = json["answer"] as? String, !answer.isEmpty {
                let response = CoreChatResponse(answer: answer, provider: "local", model: nil)
                continuation.yield(.init(text: answer, isFinal: true, response: response))
                return
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

    private func buildBody(from request: CoreChatRequest, stream: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "model": request.model,
            "messages": request.messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "stream": stream
        ]
        // Attach local controls when targeting LocalAgent-like endpoints without API key
        if apiKey == nil, endpoint.host == "127.0.0.1", endpoint.path.contains("/chat") {
            let env = ProcessInfo.processInfo.environment
            let perf = (env["ENGRAVER_PERF"] ?? "balanced").lowercased()
            var temperature = 0.8
            var topP = 0.95
            var topK = 40
            var maxTokens = 256
            switch perf {
            case "fast": temperature = 0.7; topP = 0.9; topK = 40; maxTokens = 128
            case "quality": temperature = 0.9; topP = 0.97; topK = 60; maxTokens = 512
            default: break
            }
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

    private func map(_ error: Error) -> Error {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return ProviderError.networkError(ns.localizedDescription) }
        return error
    }
}

