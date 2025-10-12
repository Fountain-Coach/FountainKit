import Foundation
import LLMGatewayAPI
import ApiClientsCore

/// Represents a single chunk of assistant output produced by the Fountain gateway.
public struct GatewayChatChunk: Sendable {
    public let text: String
    public let isFinal: Bool
    public let response: GatewayChatResponse?

    public init(text: String, isFinal: Bool, response: GatewayChatResponse?) {
        self.text = text
        self.isFinal = isFinal
        self.response = response
    }
}

/// Canonical shape of the gateway's chat response.
public struct GatewayChatResponse: Sendable {
    public let answer: String
    public let provider: String?
    public let model: String?
    public let usage: JSONValue?
    public let raw: JSONValue?
    public let functionCall: JSONValue?

    public init(answer: String,
                provider: String?,
                model: String?,
                usage: JSONValue?,
                raw: JSONValue?,
                functionCall: JSONValue?) {
        self.answer = answer
        self.provider = provider
        self.model = model
        self.usage = usage
        self.raw = raw
        self.functionCall = functionCall
    }
}

/// Async client for the Fountain gateway chat endpoint with optional streaming support.
public struct GatewayChatClient: Sendable {
    public typealias TokenProvider = @Sendable () async throws -> String?

    private let baseURL: URL
    private let tokenProvider: TokenProvider
    private let session: URLSession

    public init(baseURL: URL,
                tokenProvider: @escaping TokenProvider,
                session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
    }

    /// Streams assistant output as it is produced by the gateway.
    /// Falls back to a single final chunk when streaming is not supported by the backend.
    public func stream(request: ChatRequest, preferStreaming: Bool = true) -> AsyncThrowingStream<GatewayChatChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try await makeURLRequest(for: request, preferStreaming: preferStreaming)
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw GatewayChatError.invalidResponse
                    }

                    try validate(statusCode: http.statusCode, data: nil)

                    let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
                    if contentType.contains("text/event-stream") {
                        try await handleEventStream(bytes: bytes, continuation: continuation)
                    } else {
                        let data = try await Data(bytes: bytes)
                        let envelope = try decodeEnvelope(from: data)
                        let response = makeResponse(from: envelope)
                        continuation.yield(.init(text: response.answer, isFinal: true, response: response))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Convenience helper that waits for the final response without streaming.
    public func complete(request: ChatRequest) async throws -> GatewayChatResponse {
        let dataRequest = try await makeURLRequest(for: request, preferStreaming: false)
        let (data, response) = try await session.data(for: dataRequest)
        guard let http = response as? HTTPURLResponse else {
            throw GatewayChatError.invalidResponse
        }
        try validate(statusCode: http.statusCode, data: data)
        let envelope = try decodeEnvelope(from: data)
        return makeResponse(from: envelope)
    }

    // MARK: - Internal helpers

    private func makeURLRequest(for request: ChatRequest, preferStreaming: Bool) async throws -> URLRequest {
        var url = baseURL
        if !url.path.hasSuffix("/chat") {
            url.append(path: "/chat")
        }
        if preferStreaming {
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var query = comps?.queryItems ?? []
            query.append(.init(name: "stream", value: "1"))
            comps?.queryItems = query
            if let updated = comps?.url {
                url = updated
            }
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = try await tokenProvider() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        urlRequest.httpBody = try encoder.encode(request)
        return urlRequest
    }

    private func handleEventStream(bytes: URLSession.AsyncBytes,
                                   continuation: AsyncThrowingStream<GatewayChatChunk, Error>.Continuation) async throws {
        var buffer = ""
        var hasYielded = false

        func process(payload: String) throws {
            guard !payload.isEmpty else { return }
            let envelope = try decodeEnvelope(from: Data(payload.utf8))
            if let delta = envelope.delta?.content, !delta.isEmpty {
                continuation.yield(.init(text: delta, isFinal: false, response: nil))
                hasYielded = true
            }
            if let answer = envelope.answer, !answer.isEmpty {
                let response = makeResponse(from: envelope)
                continuation.yield(.init(text: answer, isFinal: true, response: response))
                hasYielded = true
            }
        }

        for try await line in bytes.lines {
            if line.hasPrefix("data:") {
                let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" {
                    break
                }
                try process(payload: payload)
            } else if line.isEmpty {
                if !buffer.isEmpty {
                    try process(payload: buffer)
                    buffer.removeAll()
                }
            } else {
                buffer.append(line)
            }
        }

        if !hasYielded && !buffer.isEmpty {
            let envelope = try decodeEnvelope(from: Data(buffer.utf8))
            let response = makeResponse(from: envelope)
            continuation.yield(.init(text: response.answer, isFinal: true, response: response))
        }
    }

    private func validate(statusCode: Int, data: Data?) throws {
        guard (200...299).contains(statusCode) else {
            if let data, let message = String(data: data, encoding: .utf8) {
                throw GatewayChatError.serverError(statusCode: statusCode, message: message)
            }
            throw GatewayChatError.serverError(statusCode: statusCode, message: nil)
        }
    }

    private func decodeEnvelope(from data: Data) throws -> GatewayChatEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GatewayChatEnvelope.self, from: data)
    }

    private func makeResponse(from envelope: GatewayChatEnvelope) -> GatewayChatResponse {
        GatewayChatResponse(
            answer: envelope.answer ?? envelope.delta?.content ?? "",
            provider: envelope.provider,
            model: envelope.model,
            usage: envelope.usage,
            raw: envelope.raw,
            functionCall: envelope.function_call ?? envelope.delta?.function_call
        )
    }
}

// MARK: - Models & Errors

private struct GatewayChatEnvelope: Decodable {
    let answer: String?
    let provider: String?
    let model: String?
    let usage: JSONValue?
    let raw: JSONValue?
    let function_call: JSONValue?
    let delta: GatewayChatDelta?
}

private struct GatewayChatDelta: Decodable {
    let content: String?
    let function_call: JSONValue?
}

public enum GatewayChatError: LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int, message: String?)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Gateway did not return a valid HTTP response."
        case .serverError(let status, let message):
            if let message, !message.isEmpty {
                return "Gateway returned status \(status): \(message)"
            }
            return "Gateway returned status \(status)."
        }
    }
}

private extension Data {
    init(bytes: URLSession.AsyncBytes) async throws {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        self = data
    }
}
