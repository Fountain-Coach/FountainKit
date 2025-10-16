import Foundation
import FountainRuntime
import LLMGatewayPlugin

/// Plugin exposing gateway endpoints compatible with the ChatKit front-end.
public struct ChatKitGatewayPlugin: Sendable {
    public let router: Router

    public init(store: ChatKitSessionStore = ChatKitSessionStore(),
                uploadStore: ChatKitUploadStore = ChatKitUploadStore()) {
        self.router = Router(handlers: Handlers(store: store,
                                                uploadStore: uploadStore,
                                                responder: LLMChatResponder()))
    }

    init(store: ChatKitSessionStore,
         uploadStore: ChatKitUploadStore,
         responder: any ChatResponder) {
        self.router = Router(handlers: Handlers(store: store,
                                                uploadStore: uploadStore,
                                                responder: responder))
    }
}

// MARK: - Router

public struct Router: Sendable {
    let handlers: Handlers

    init(handlers: Handlers) {
        self.handlers = handlers
    }

    /// Routes ChatKit-specific requests to the appropriate handler.
    /// - Parameter request: Incoming gateway request.
    /// - Returns: Response when the route is handled, otherwise `nil`.
    public func route(_ request: HTTPRequest) async throws -> HTTPResponse? {
        let pathOnly = request.path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? request.path
        let segments = pathOnly.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        guard !segments.isEmpty, segments[0] == "chatkit" else { return nil }

        switch (request.method, segments) {
        case ("POST", ["chatkit", "session"]):
            return await handlers.startSession(request)
        case ("POST", ["chatkit", "session", "refresh"]):
            return await handlers.refreshSession(request)
        case ("POST", ["chatkit", "messages"]):
            return await handlers.postMessage(request)
        case ("POST", ["chatkit", "upload"]):
            return await handlers.uploadAttachment(request)
        default:
            return nil
        }
    }
}

// MARK: - Responder Abstractions

/// Normalised result returned by a chat responder.
struct ChatResponderResult: Sendable {
    public let answer: String
    public let provider: String?
    public let model: String?
    public let usage: [String: Double]?
}

/// Strategy interface used to fulfil ChatKit message requests.
protocol ChatResponder: Sendable {
    func respond(session: ChatKitSessionStore.StoredSession,
                 request: ChatKitMessageRequest,
                 preferStreaming: Bool) async throws -> ChatResponderResult
}

/// Default responder that forwards requests to the LLM Gateway plugin.
struct LLMChatResponder: ChatResponder {
    private let call: @Sendable (HTTPRequest, ChatRequest) async throws -> HTTPResponse
    private let defaultModel: String

    init(plugin: LLMGatewayPlugin = LLMGatewayPlugin(),
         defaultModel: String? = nil) {
        let handlers = plugin.router.handlers
        self.call = { request, body in
            try await handlers.chatWithObjective(request, body: body)
        }
        self.defaultModel = defaultModel
            ?? ProcessInfo.processInfo.environment["CHATKIT_DEFAULT_MODEL"]
            ?? "gpt-4o-mini"
    }

    func respond(session: ChatKitSessionStore.StoredSession,
                 request: ChatKitMessageRequest,
                 preferStreaming: Bool) async throws -> ChatResponderResult {
        let modelHint = request.metadata?["model"] ?? session.metadata["model"]
        let model = (modelHint?.isEmpty == false) ? modelHint! : defaultModel

        let llmMessages = request.messages.map { MessageObject(role: $0.role, content: $0.content) }
        let chatRequest = ChatRequest(model: model, messages: llmMessages)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(chatRequest)
        let httpRequest = HTTPRequest(
            method: "POST",
            path: "/chat",
            headers: ["Content-Type": "application/json"],
            body: body
        )

        let response = try await call(httpRequest, chatRequest)
        guard (200...299).contains(response.status) else {
            throw ChatKitGatewayError.llmFailure(status: response.status)
        }

        return try decodeLLMResponse(response.body, contentType: response.headers["Content-Type"])
    }

    private func decodeLLMResponse(_ data: Data, contentType: String?) throws -> ChatResponderResult {
        if let contentType, contentType.contains("text/event-stream") {
            return try decodeSSEPayload(data)
        }
        return try decodeJSONPayload(data)
    }

    private func decodeJSONPayload(_ data: Data) throws -> ChatResponderResult {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChatKitGatewayError.invalidResponse("non JSON body")
        }

        let answer = extractAnswer(from: object)
        guard let answer else {
            throw ChatKitGatewayError.invalidResponse("missing answer")
        }

        let provider = object["provider"] as? String
        let model = object["model"] as? String
        let usage = extractUsage(from: object["usage"])

        return ChatResponderResult(answer: answer,
                                   provider: provider,
                                   model: model,
                                   usage: usage)
    }

    private func decodeSSEPayload(_ data: Data) throws -> ChatResponderResult {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ChatKitGatewayError.invalidResponse("invalid SSE payload")
        }
        var answerFragments: [String] = []
        var provider: String?
        var model: String?
        var usage: [String: Double]?

        for block in text.components(separatedBy: "\n\n") {
            for line in block.split(whereSeparator: \.isNewline) {
                guard line.starts(with: "data:") else { continue }
                let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { continue }
                guard let jsonData = payload.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                    continue
                }
                if let delta = (object["delta"] as? [String: Any])?["content"] as? String {
                    answerFragments.append(delta)
                }
                if let finalAnswer = object["answer"] as? String {
                    answerFragments.append(finalAnswer)
                }
                if provider == nil { provider = object["provider"] as? String }
                if model == nil { model = object["model"] as? String }
                if usage == nil, let rawUsage = object["usage"] {
                    usage = extractUsage(from: rawUsage)
                }
            }
        }

        let answer = answerFragments.joined()
        guard !answer.isEmpty else {
            throw ChatKitGatewayError.invalidResponse("empty SSE answer")
        }
        return ChatResponderResult(answer: answer,
                                   provider: provider,
                                   model: model,
                                   usage: usage)
    }

    private func extractAnswer(from object: [String: Any]) -> String? {
        if let answer = object["answer"] as? String, !answer.isEmpty {
            return answer
        }
        if let choices = object["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any] {
            if let content = message["content"] as? String, !content.isEmpty {
                return content
            }
        }
        return nil
    }

    private func extractUsage(from raw: Any?) -> [String: Double]? {
        guard let dict = raw as? [String: Any] else { return nil }
        var usage: [String: Double] = [:]
        for (key, value) in dict {
            if let number = value as? NSNumber {
                usage[key] = number.doubleValue
            } else if let str = value as? String, let dbl = Double(str) {
                usage[key] = dbl
            }
        }
        return usage.isEmpty ? nil : usage
    }
}

// MARK: - Gateway Handlers

struct Handlers: Sendable {
    private let store: ChatKitSessionStore
    private let uploadStore: ChatKitUploadStore
    private let responder: any ChatResponder

    public init(store: ChatKitSessionStore,
                uploadStore: ChatKitUploadStore,
                responder: any ChatResponder) {
        self.store = store
        self.uploadStore = uploadStore
        self.responder = responder
    }

    public func startSession(_ request: HTTPRequest) async -> HTTPResponse {
        let payload: ChatKitSessionRequest?
        if request.body.isEmpty {
            payload = nil
        } else {
            do {
                payload = try JSONDecoder().decode(ChatKitSessionRequest.self, from: request.body)
            } catch {
                return makeError(status: 400, code: "invalid_request", message: "invalid session payload")
            }
        }

        let descriptor = await store.createSession(
            persona: payload?.persona,
            userId: payload?.userId,
            metadata: payload?.metadata ?? [:]
        )
        let response = ChatKitSessionResponse(session: descriptor)
        return encodeJSON(response, status: 201)
    }

    public func refreshSession(_ request: HTTPRequest) async -> HTTPResponse {
        guard
            let payload = try? JSONDecoder().decode(ChatKitSessionRefreshRequest.self, from: request.body)
        else {
            return makeError(status: 400, code: "invalid_request", message: "missing client_secret")
        }

        guard let descriptor = await store.refresh(secret: payload.client_secret) else {
            return makeError(status: 401, code: "invalid_secret", message: "client secret expired or unknown")
        }
        let response = ChatKitSessionResponse(session: descriptor)
        return encodeJSON(response, status: 200)
    }

    public func postMessage(_ request: HTTPRequest) async -> HTTPResponse {
        guard let payload = try? JSONDecoder().decode(ChatKitMessageRequest.self, from: request.body) else {
            return makeError(status: 400, code: "invalid_request", message: "invalid message payload")
        }
        guard let session = await store.session(for: payload.client_secret) else {
            return makeError(status: 401, code: "invalid_secret", message: "client secret expired or unknown")
        }

        let preferStreaming = payload.stream ?? true
        let mergedMetadata = mergeMetadata(session.metadata, payload.metadata)
        let threadId = payload.thread_id ?? session.id
        let responseId = UUID().uuidString.lowercased()
        let createdAt = isoTimestamp()

        do {
            let result = try await responder.respond(session: session,
                                                     request: payload,
                                                     preferStreaming: preferStreaming)
            if preferStreaming {
                return makeStreamResponse(answer: result.answer,
                                          provider: result.provider,
                                          model: result.model,
                                          usage: result.usage,
                                          threadId: threadId,
                                          responseId: responseId,
                                          createdAt: createdAt,
                                          metadata: mergedMetadata)
            } else {
                let response = ChatKitMessageResponse(answer: result.answer,
                                                      thread_id: threadId,
                                                      response_id: responseId,
                                                      created_at: createdAt,
                                                      provider: result.provider,
                                                      model: result.model,
                                                      usage: result.usage,
                                                      metadata: mergedMetadata)
                return encodeJSON(response, status: 200)
            }
        } catch {
            return makeError(status: 502, code: "llm_error", message: error.localizedDescription)
        }
    }

    public func uploadAttachment(_ request: HTTPRequest) async -> HTTPResponse {
        guard let contentType = request.headers["Content-Type"],
              contentType.starts(with: "multipart/form-data") else {
            return makeError(status: 400, code: "invalid_request", message: "multipart/form-data required")
        }

        guard let boundary = parseBoundary(from: contentType) else {
            return makeError(status: 400, code: "invalid_request", message: "multipart boundary missing")
        }

        guard let multipart = parseMultipart(body: request.body, boundary: boundary) else {
            return makeError(status: 400, code: "invalid_request", message: "malformed multipart payload")
        }

        guard let secretPart = multipart.first(where: { $0.name == "client_secret" }),
              let clientSecret = String(data: secretPart.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clientSecret.isEmpty else {
            return makeError(status: 400, code: "invalid_request", message: "client_secret part missing")
        }

        guard let session = await store.session(for: clientSecret) else {
            return makeError(status: 401, code: "invalid_secret", message: "client secret expired or unknown")
        }

        let threadId = multipart.first(where: { $0.name == "thread_id" })
            .flatMap { String(data: $0.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard let filePart = multipart.first(where: { $0.name == "file" }) else {
            return makeError(status: 400, code: "invalid_request", message: "file part missing")
        }

        let fileName = filePart.filename ?? "attachment"
        let mimeType = filePart.contentType ?? "application/octet-stream"

        let descriptor = await uploadStore.store(fileName: fileName,
                                                 mimeType: mimeType,
                                                 data: filePart.data,
                                                 sessionId: session.id,
                                                 threadId: threadId)

        let response = ChatKitUploadResponse(attachment_id: descriptor.id,
                                             upload_url: descriptor.url,
                                             mime_type: descriptor.mimeType)
        return encodeJSON(response, status: 201)
    }

    private func encodeJSON<T: Encodable>(_ value: T, status: Int) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(value)) ?? Data()
        return HTTPResponse(
            status: status,
            headers: ["Content-Type": "application/json", "Cache-Control": "no-store"],
            body: data
        )
    }

    private func makeError(status: Int, code: String, message: String) -> HTTPResponse {
        let payload = ChatKitErrorResponse(error: message, code: code)
        return encodeJSON(payload, status: status)
    }

    private func mergeMetadata(_ session: [String: String],
                               _ request: [String: String]?) -> [String: String]? {
        var combined = session
        if let request {
            for (key, value) in request { combined[key] = value }
        }
        return combined.isEmpty ? nil : combined
    }

    private func isoTimestamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func makeStreamResponse(answer: String,
                                    provider: String?,
                                    model: String?,
                                    usage: [String: Double]?,
                                    threadId: String,
                                    responseId: String,
                                    createdAt: String,
                                    metadata: [String: String]?) -> HTTPResponse {
        var metadataBlock = metadata ?? [:]
        if let provider { metadataBlock["provider"] = provider }
        if let model { metadataBlock["model"] = model }
        if let usage {
            for (key, value) in usage {
                metadataBlock["usage.\(key)"] = String(value)
            }
        }
        let envelopeMetadata = metadataBlock.isEmpty ? nil : metadataBlock

        let deltaEvent = ChatKitStreamEventEnvelope(
            id: UUID().uuidString.lowercased(),
            event: "delta",
            delta: .init(content: answer),
            answer: nil,
            done: nil,
            thread_id: nil,
            response_id: nil,
            created_at: nil,
            metadata: nil
        )

        let completionEvent = ChatKitStreamEventEnvelope(
            id: UUID().uuidString.lowercased(),
            event: "completion",
            delta: nil,
            answer: answer,
            done: true,
            thread_id: threadId,
            response_id: responseId,
            created_at: createdAt,
            metadata: envelopeMetadata
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let events = [deltaEvent, completionEvent]
        var body = ""
        for event in events {
            guard let data = try? encoder.encode(event),
                  let json = String(data: data, encoding: .utf8) else { continue }
            if let id = event.id {
                body += "id: \(id)\n"
            }
            body += "event: \(event.event)\n"
            body += "data: \(json)\n\n"
        }

        return HTTPResponse(
            status: 202,
            headers: [
                "Content-Type": "text/event-stream",
                "Cache-Control": "no-store",
                "Connection": "keep-alive"
            ],
            body: Data(body.utf8)
        )
    }

    private func parseBoundary(from contentType: String) -> String? {
        contentType
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { $0.starts(with: "boundary=") })?
            .replacingOccurrences(of: "boundary=", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private func parseMultipart(body: Data, boundary: String) -> [MultipartPart]? {
        guard var raw = String(data: body, encoding: .utf8) else { return nil }
        raw = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let delimiter = "--" + boundary
        var parts: [MultipartPart] = []
        for segment in raw.components(separatedBy: delimiter) {
            var section = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            if section == "--" || section.isEmpty { continue }
            if section.hasSuffix("--") {
                section.removeLast(2)
                section = section.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !section.isEmpty else { continue }

            let pieces = section.components(separatedBy: "\n\n")
            guard pieces.count >= 2 else { return nil }
            let headerLines = pieces[0].components(separatedBy: "\n")
            let bodySection = pieces.dropFirst().joined(separator: "\n\n")

            let headers = headerLines.reduce(into: [String: String]()) { dict, line in
                let comps = line.split(separator: ":", maxSplits: 1)
                guard comps.count == 2 else { return }
                dict[String(comps[0]).lowercased()] = String(comps[1]).trimmingCharacters(in: .whitespaces)
            }

            guard let disposition = headers["content-disposition"],
                  let attributes = parseContentDisposition(disposition),
                  let name = attributes["name"] else { return nil }

            let filename = attributes["filename"]
            let contentType = headers["content-type"]
            var dataString = bodySection
            while dataString.hasSuffix("\n") { dataString.removeLast() }
            let data = Data(dataString.utf8)
            parts.append(MultipartPart(name: name, filename: filename, contentType: contentType, data: data))
        }
        return parts
    }

    private func parseContentDisposition(_ header: String) -> [String: String]? {
        var result: [String: String] = [:]
        for component in header.split(separator: ";") {
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            result[key] = value
        }
        return result.isEmpty ? nil : result
    }

    private struct MultipartPart {
        let name: String
        let filename: String?
        let contentType: String?
        let data: Data
    }
}

// MARK: - Session Store

public actor ChatKitSessionStore {
    public struct StoredSession: Sendable {
        public let id: String
        public let secret: String
        public let expiresAt: Date
        public let metadata: [String: String]
    }

    private var sessions: [String: StoredSession] = [:]
    private var secrets: [String: String] = [:] // secret -> session id
    private let ttl: TimeInterval
    private let clock: () -> Date

    public init(ttl: TimeInterval = 15 * 60, clock: @escaping () -> Date = Date.init) {
        self.ttl = ttl
        self.clock = clock
    }

    public func createSession(persona: String?, userId: String?, metadata: [String: String]) -> StoredSession {
        var meta = metadata
        if let persona { meta["persona"] = persona }
        if let userId { meta["user_id"] = userId }

        let sessionId = UUID().uuidString.lowercased()
        let secret = issueSecret()
        let expires = clock().addingTimeInterval(ttl)

        let stored = StoredSession(id: sessionId, secret: secret, expiresAt: expires, metadata: meta)
        sessions[sessionId] = stored
        secrets[secret] = sessionId
        return stored
    }

    public func refresh(secret: String) -> StoredSession? {
        guard let sessionId = secrets[secret], let stored = sessions[sessionId] else {
            return nil
        }
        guard stored.expiresAt >= clock() else {
            sessions.removeValue(forKey: sessionId)
            secrets.removeValue(forKey: secret)
            return nil
        }

        secrets.removeValue(forKey: secret)
        let newSecret = issueSecret()
        let refreshed = StoredSession(
            id: stored.id,
            secret: newSecret,
            expiresAt: clock().addingTimeInterval(ttl),
            metadata: stored.metadata
        )
        sessions[sessionId] = refreshed
        secrets[newSecret] = sessionId
        return refreshed
    }

    public func session(for secret: String) -> StoredSession? {
        guard let sessionId = secrets[secret], let stored = sessions[sessionId] else {
            return nil
        }
        guard stored.expiresAt >= clock() else {
            sessions.removeValue(forKey: sessionId)
            secrets.removeValue(forKey: secret)
            return nil
        }
        return stored
    }

    private func issueSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: UInt8.min...UInt8.max)
        }
        return Data(bytes).base64EncodedString()
    }
}

// MARK: - Upload Store

public actor ChatKitUploadStore {
    public struct StoredAttachment: Sendable {
        public let id: String
        public let fileName: String
        public let mimeType: String
        public let data: Data
        public let sessionId: String
        public let threadId: String?
    }

    public struct Descriptor: Sendable {
        public let id: String
        public let url: String
        public let mimeType: String?
    }

    private var attachments: [String: StoredAttachment] = [:]

    public init() {}

    public func store(fileName: String,
                      mimeType: String?,
                      data: Data,
                      sessionId: String,
                      threadId: String?) -> Descriptor {
        let attachmentId = UUID().uuidString.lowercased()
        let stored = StoredAttachment(id: attachmentId,
                                      fileName: fileName,
                                      mimeType: mimeType ?? "application/octet-stream",
                                      data: data,
                                      sessionId: sessionId,
                                      threadId: threadId)
        attachments[attachmentId] = stored
        let url = "memory://chatkit-attachments/" + attachmentId
        return Descriptor(id: attachmentId, url: url, mimeType: stored.mimeType)
    }
}

// MARK: - Models & Errors

struct ChatKitSessionRequest: Decodable {
    let persona: String?
    let userId: String?
    let metadata: [String: String]?
}

struct ChatKitSessionRefreshRequest: Decodable {
    let client_secret: String
}

struct ChatKitSessionResponse: Encodable {
    let session_id: String
    let client_secret: String
    let expires_at: String
    let metadata: [String: String]?

    init(session: ChatKitSessionStore.StoredSession) {
        session_id = session.id
        client_secret = session.secret
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        expires_at = formatter.string(from: session.expiresAt)
        metadata = session.metadata.isEmpty ? nil : session.metadata
    }
}

struct ChatKitErrorResponse: Encodable {
    let error: String
    let code: String
}

struct ChatKitMessageRequest: Decodable {
    let client_secret: String
    let thread_id: String?
    let messages: [ChatKitMessage]
    let stream: Bool?
    let metadata: [String: String]?
}

struct ChatKitMessage: Decodable {
    let id: String?
    let role: String
    let content: String
    let created_at: String?
    let attachments: [ChatKitAttachment]?
}

struct ChatKitAttachment: Decodable {
    let id: String
    let type: String
    let name: String?
    let mime_type: String?
    let size_bytes: Int?
}

struct ChatKitMessageResponse: Encodable {
    let answer: String
    let thread_id: String
    let response_id: String
    let created_at: String
    let provider: String?
    let model: String?
    let usage: [String: Double]?
    let metadata: [String: String]?
}

struct ChatKitStreamEventEnvelope: Encodable {
    let id: String?
    let event: String
    let delta: ChatKitStreamDelta?
    let answer: String?
    let done: Bool?
    let thread_id: String?
    let response_id: String?
    let created_at: String?
    let metadata: [String: String]?
}

struct ChatKitStreamDelta: Encodable {
    let content: String
}

struct ChatKitUploadResponse: Encodable {
    let attachment_id: String
    let upload_url: String
    let mime_type: String?
}

enum ChatKitGatewayError: Error, LocalizedError {
    case llmFailure(status: Int)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .llmFailure(let status):
            return "LLM gateway failed with status \(status)"
        case .invalidResponse(let reason):
            return "Invalid LLM response: \(reason)"
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
