import AsyncHTTPClient
import Foundation
import FountainAICore
import NIOCore

/// Minimal OpenAI-compatible chat provider implementing CoreChatStreaming.
/// Works with hosted OpenAI (when apiKey is set) and OpenAI-compatible local runtimes (when apiKey is nil).
public final class OpenAICompatibleChatProvider {
    private let apiKey: String?
    private let endpoint: URL
    private let client: HTTPClient
    private let ownsClient: Bool

    public init(
        apiKey: String?,
        endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!,
        httpClient: HTTPClient? = nil
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        if let httpClient {
            self.client = httpClient
            self.ownsClient = false
        } else {
            self.client = HTTPClient(eventLoopGroupProvider: .singleton)
            self.ownsClient = true
        }
    }

    deinit {
        guard ownsClient else { return }
        let client = self.client
        Task.detached {
            try? await client.shutdown()
        }
    }
}

extension OpenAICompatibleChatProvider: CoreChatStreaming {
    public func complete(request: CoreChatRequest) async throws -> CoreChatResponse {
        let bodyData = try JSONSerialization.data(withJSONObject: buildBody(from: request, stream: false))
        var req = HTTPClientRequest(url: endpoint.absoluteString)
        req.method = .POST
        req.headers.add(name: "Content-Type", value: "application/json")
        if let apiKey, !apiKey.isEmpty {
            req.headers.add(name: "Authorization", value: "Bearer \(apiKey)")
        }
        req.body = .bytes(bodyData)
        do {
            let resp = try await client.execute(req, timeout: .seconds(60))
            let data = try await resp.bodyData()
            guard (200...299).contains(Int(resp.status.code)) else {
                throw ProviderError.serverError(
                    statusCode: Int(resp.status.code),
                    message: String(data: data, encoding: .utf8)
                )
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

    private func streamSSE(
        request: CoreChatRequest,
        continuation: AsyncThrowingStream<CoreChatChunk, Error>.Continuation
    ) async throws {
        let bodyData = try JSONSerialization.data(withJSONObject: buildBody(from: request, stream: true))
        var req = HTTPClientRequest(url: endpoint.absoluteString)
        req.method = .POST
        req.headers.add(name: "Content-Type", value: "application/json")
        if let apiKey, !apiKey.isEmpty {
            req.headers.add(name: "Authorization", value: "Bearer \(apiKey)")
        }
        req.body = .bytes(bodyData)
        let resp = try await client.execute(req, timeout: .seconds(60))
        guard (200...299).contains(Int(resp.status.code)) else {
            throw ProviderError.serverError(statusCode: Int(resp.status.code), message: nil)
        }

        var pending = ""
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

        guard let bodyStream = resp.body else {
            continuation.finish(throwing: ProviderError.invalidResponse)
            return
        }

        for try await chunk in bodyStream {
            pending.append(String(decoding: chunk.readableBytesView, as: UTF8.self))
            while let range = pending.range(of: "\n") {
                var line = String(pending[..<range.lowerBound])
                pending = String(pending[range.upperBound...])
                if line.hasSuffix("\r") { line.removeLast() }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("data:") {
                    let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if payload == "[DONE]" {
                        continuation.finish()
                        return
                    }
                    if !buffer.isEmpty { buffer.append("\n") }
                    buffer.append(payload)
                } else if trimmed.isEmpty {
                    if !buffer.isEmpty {
                        process(buffer)
                        buffer.removeAll(keepingCapacity: true)
                    }
                }
            }
        }

        if !buffer.isEmpty {
            process(buffer)
        }
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
        if let httpError = error as? HTTPClientError {
            return ProviderError.networkError(httpError.localizedDescription)
        }
        if let nioError = error as? NIOConnectionError {
            return ProviderError.networkError(nioError.localizedDescription)
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return ProviderError.networkError(ns.localizedDescription) }
        return error
    }
}

private extension HTTPClientResponse {
    func bodyData() async throws -> Data {
        guard var stream = body else { return Data() }
        var collected = Data()
        collected.reserveCapacity(1024)
        for try await chunk in stream {
            collected.append(contentsOf: chunk.readableBytesView)
        }
        return collected
    }
}

extension OpenAICompatibleChatProvider: @unchecked Sendable {}

