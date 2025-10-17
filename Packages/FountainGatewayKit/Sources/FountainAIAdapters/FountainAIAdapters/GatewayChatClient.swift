import Foundation
import LLMGatewayAPI
import OpenAPIURLSession
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
        // Use generated OpenAPI client for non-streaming calls
        var headers: [String: String] = ["Accept": "application/json"]
        if let token = try await tokenProvider(), !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }

        let transport = URLSessionTransport()
        let middlewares = APIClientHelpers.defaultMiddlewares(defaultHeaders: headers)
        let client = LLMGatewayAPI.Client(serverURL: baseURL, transport: transport, middlewares: middlewares)

        // Map manual ChatRequest into generated schema
        let genMessages = request.messages.map { m in
            LLMGatewayAPI.Components.Schemas.MessageObject(role: m.role, content: m.content)
        }
        let genFunctions = request.functions?.map { f in
            LLMGatewayAPI.Components.Schemas.FunctionObject(name: f.name, description: f.description)
        }
        let genFunctionCall: LLMGatewayAPI.Components.Schemas.ChatRequest.function_callPayload?
        if let fc = request.function_call {
            switch fc {
            case .left(let value):
                genFunctionCall = (value == "auto") ? .case1(.auto) : nil
            case .right(let obj):
                genFunctionCall = .FunctionCallObject(.init(name: obj.name))
            }
        } else {
            genFunctionCall = nil
        }
        let genBody = LLMGatewayAPI.Components.Schemas.ChatRequest(
            model: request.model,
            messages: genMessages,
            functions: genFunctions,
            function_call: genFunctionCall
        )

        let output = try await client.chatWithObjective(.init(body: .json(genBody)))
        func toJSONValue<T: Encodable>(_ value: T?) -> JSONValue? {
            guard let value else { return nil }
            if let data = try? JSONEncoder().encode(value) {
                return try? JSONDecoder().decode(JSONValue.self, from: data)
            }
            return nil
        }

        switch output {
        case .ok(let ok):
            // Map generated response to adapter response
            let payload = try ok.body.json
            let answer = payload.answer ?? payload.delta?.content ?? ""
            let provider = payload.provider
            let model = payload.model
            // usage/raw/function_call are free-form objects -> map to JSONValue via encoding round-trip
            let usage = toJSONValue(payload.usage)
            let raw = toJSONValue(payload.raw)
            let functionCall = toJSONValue(payload.function_call)
            return GatewayChatResponse(answer: answer, provider: provider, model: model, usage: usage, raw: raw, functionCall: functionCall)
        case .badRequest:
            throw GatewayChatError.serverError(statusCode: 400, message: "Bad Request")
        case .unprocessableContent:
            throw GatewayChatError.serverError(statusCode: 422, message: "Validation Error")
        case .undocumented(let status, _):
            throw GatewayChatError.serverError(statusCode: status, message: nil)
        }
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

        func emit(envelope: GatewayChatEnvelope) {
            if let delta = envelope.delta?.content, !delta.isEmpty {
                continuation.yield(.init(text: delta, isFinal: false, response: nil))
            }
            if let answer = envelope.answer, !answer.isEmpty {
                let response = makeResponse(from: envelope)
                continuation.yield(.init(text: answer, isFinal: true, response: response))
            }
        }

        func process(payload: String) throws {
            let cleaned = payload.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return }

            do {
                let envelope = try decodeEnvelope(from: Data(cleaned.utf8))
                emit(envelope: envelope)
                return
            } catch {
                var didEmit = false
                let fragments = cleaned.split(separator: "\n")
                for fragment in fragments {
                    let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
                    if let envelope = try? decodeEnvelope(from: data) {
                        emit(envelope: envelope)
                        didEmit = true
                    }
                }
                if didEmit {
                    return
                }
                throw error
            }
        }

        for try await rawLine in bytes.lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("event:") {
                // Ignore event lines for now; payloads arrive via data fields.
                continue
            } else if line.hasPrefix("data:") {
                let value = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                if value == "[DONE]" {
                    break
                }
                if !buffer.isEmpty {
                    buffer.append("\n")
                }
                buffer.append(value)
            } else if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !buffer.isEmpty {
                    try process(payload: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
        }

        if !buffer.isEmpty {
            try process(payload: buffer)
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
        if let envelope = try? decoder.decode(GatewayChatEnvelope.self, from: data),
           envelope.containsContent {
            return envelope
        }
        if let fallback = try? decoder.decode(OpenAIChatCompletionEnvelope.self, from: data) {
            return fallback.toGatewayEnvelope(rawData: data)
        }
        if let fallback = decodeOpenAIEnvelopeFallback(from: data) {
            return fallback
        }
        let message = String(data: data, encoding: .utf8)
        throw GatewayChatError.serverError(statusCode: 200, message: message)
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

private extension GatewayChatEnvelope {
    var containsContent: Bool {
        if let answer, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let delta {
            if let content = delta.content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
            if delta.function_call != nil { return true }
        }
        if function_call != nil { return true }
        return false
    }
}

private struct GatewayChatDelta: Decodable {
    let content: String?
    let function_call: JSONValue?
}

private extension GatewayChatEnvelope {
    init(answer: String?,
         provider: String?,
         model: String?,
         usage: JSONValue?,
         raw: JSONValue?,
         functionCall: JSONValue?,
         delta: GatewayChatDelta?) {
        self.answer = answer
        self.provider = provider
        self.model = model
        self.usage = usage
        self.raw = raw
        self.function_call = functionCall
        self.delta = delta
    }
}

private struct OpenAIChatCompletionEnvelope: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String?
            let content: String?
            let function_call: JSONValue?
        }

        struct Delta: Decodable {
            let role: String?
            let content: String?
            let function_call: JSONValue?
        }

        let index: Int?
        let message: Message?
        let delta: Delta?
        let finish_reason: String?
    }

    let id: String?
    let model: String?
    let choices: [Choice]
    let usage: JSONValue?

    func toGatewayEnvelope(rawData: Data) -> GatewayChatEnvelope {
        let choice = choices.first
        let message = choice?.message
        let delta = choice?.delta
        let answer = message?.content ?? delta?.content ?? ""
        let functionCall = message?.function_call ?? delta?.function_call
        let raw = (try? JSONDecoder().decode(JSONValue.self, from: rawData))

        let gatewayDelta: GatewayChatDelta?
        if let delta {
            gatewayDelta = GatewayChatDelta(content: delta.content, function_call: delta.function_call)
        } else {
            gatewayDelta = nil
        }

        return GatewayChatEnvelope(
            answer: answer,
            provider: guessProvider(for: model),
            model: model,
            usage: usage,
            raw: raw,
            functionCall: functionCall,
            delta: gatewayDelta
        )
    }
}

private func guessProvider(for model: String?) -> String? {
    guard let model else { return nil }
    let lowered = model.lowercased()
    if lowered.contains("gpt") || lowered.contains("openai") {
        return "openai"
    }
    return nil
}

private func decodeOpenAIEnvelopeFallback(from data: Data) -> GatewayChatEnvelope? {
    guard
        let json = try? JSONSerialization.jsonObject(with: data),
        let object = json as? [String: Any]
    else {
        return nil
    }

    let choices = object["choices"] as? [[String: Any]]
    let first = choices?.first
    let message = first?["message"] as? [String: Any]
    let delta = first?["delta"] as? [String: Any]

    let answer = (message?["content"] as? String) ?? (delta?["content"] as? String) ?? ""
    let functionCallAny = message?["function_call"] ?? delta?["function_call"]

    let gatewayDelta: GatewayChatDelta?
    if let delta {
        gatewayDelta = GatewayChatDelta(
            content: delta["content"] as? String,
            function_call: JSONValue(jsonObject: delta["function_call"])
        )
    } else {
        gatewayDelta = nil
    }

    let model = object["model"] as? String

    return GatewayChatEnvelope(
        answer: answer,
        provider: guessProvider(for: model),
        model: model,
        usage: JSONValue(jsonObject: object["usage"]),
        raw: JSONValue(jsonObject: object),
        functionCall: JSONValue(jsonObject: functionCallAny),
        delta: gatewayDelta
    )
}

private extension JSONValue {
    init?(jsonObject: Any?) {
        guard let jsonObject else { return nil }
        switch jsonObject {
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        case let value as [String: Any]:
            var mapped: [String: JSONValue] = [:]
            for (key, item) in value {
                if let converted = JSONValue(jsonObject: item) {
                    mapped[key] = converted
                }
            }
            self = .object(mapped)
        case let value as [Any]:
            let converted = value.compactMap { JSONValue(jsonObject: $0) }
            self = .array(converted)
        case _ as NSNull:
            self = .null
        default:
            return nil
        }
    }
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

/// Lightweight abstraction so higher level presenters can be tested by
/// providing a fake chat client without depending on `URLSession`.
public protocol GatewayChatStreaming: Sendable {
    func stream(request: ChatRequest, preferStreaming: Bool) -> AsyncThrowingStream<GatewayChatChunk, Error>
    func complete(request: ChatRequest) async throws -> GatewayChatResponse
}

extension GatewayChatClient: GatewayChatStreaming {}
