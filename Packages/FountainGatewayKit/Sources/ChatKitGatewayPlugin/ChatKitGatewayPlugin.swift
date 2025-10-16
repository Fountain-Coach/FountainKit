import Foundation
import FountainRuntime

/// Plugin exposing gateway endpoints compatible with the ChatKit front-end.
public struct ChatKitGatewayPlugin: Sendable {
    public let router: Router

    public init(store: ChatKitSessionStore = ChatKitSessionStore()) {
        self.router = Router(handlers: Handlers(store: store))
    }
}

// MARK: - Router

public struct Router: Sendable {
    let handlers: Handlers

    public init(handlers: Handlers) {
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

// MARK: - Handlers

public struct Handlers: Sendable {
    private let store: ChatKitSessionStore

    public init(store: ChatKitSessionStore) {
        self.store = store
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

        let threadId = payload.thread_id ?? session.id
        let responseId = UUID().uuidString.lowercased()
        let createdAt = isoTimestamp()
        let answer = deriveAnswer(from: payload.messages)
        let metadata = session.metadata.isEmpty ? nil : session.metadata

        if payload.stream ?? true {
            return makeStreamResponse(answer: answer,
                                      threadId: threadId,
                                      responseId: responseId,
                                      createdAt: createdAt,
                                      metadata: metadata)
        } else {
            let response = ChatKitMessageResponse(answer: answer,
                                                  thread_id: threadId,
                                                  response_id: responseId,
                                                  created_at: createdAt,
                                                  provider: "fountainkit",
                                                  model: "echo",
                                                  usage: nil,
                                                  metadata: metadata)
            return encodeJSON(response, status: 200)
        }
    }

    public func uploadAttachment(_ request: HTTPRequest) async -> HTTPResponse {
        makeError(status: 501, code: "not_implemented", message: "attachment uploads not implemented")
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

    private func deriveAnswer(from messages: [ChatKitMessage]) -> String {
        messages.last(where: { $0.role.lowercased() == "user" })?.content ?? ""
    }

    private func isoTimestamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func makeStreamResponse(answer: String,
                                    threadId: String,
                                    responseId: String,
                                    createdAt: String,
                                    metadata: [String: String]?) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

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
            metadata: metadata
        )

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

// MARK: - Models

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

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
