import Foundation

/// Minimal, shared chat DTOs and protocol that providers depend on.
/// These contracts intentionally avoid any dependency on gateway adapters or generated clients.
public struct CoreChatMessage: Sendable, Equatable {
    public enum Role: String, Sendable { case system, user, assistant }
    public var role: Role
    public var content: String
    public init(role: Role, content: String) { self.role = role; self.content = content }
}

public struct CoreChatRequest: Sendable, Equatable {
    public var model: String
    public var messages: [CoreChatMessage]
    public init(model: String, messages: [CoreChatMessage]) {
        self.model = model
        self.messages = messages
    }
}

public struct CoreChatResponse: Sendable, Equatable {
    public var answer: String
    public var provider: String?
    public var model: String?
    public init(answer: String, provider: String?, model: String?) {
        self.answer = answer
        self.provider = provider
        self.model = model
    }
}

public struct CoreChatChunk: Sendable, Equatable {
    public var text: String
    public var isFinal: Bool
    public var response: CoreChatResponse?
    public init(text: String, isFinal: Bool, response: CoreChatResponse?) {
        self.text = text
        self.isFinal = isFinal
        self.response = response
    }
}

/// Provider-facing chat streaming protocol used across apps and kits.
public protocol CoreChatStreaming: Sendable {
    func stream(request: CoreChatRequest, preferStreaming: Bool) -> AsyncThrowingStream<CoreChatChunk, Error>
    func complete(request: CoreChatRequest) async throws -> CoreChatResponse
}

/// Provider error cases common across transports.
public enum ProviderError: Error, Sendable, Equatable {
    case serverError(statusCode: Int, message: String?)
    case invalidResponse
    case networkError(String)
}

/// Lightweight telemetry event used for client-side diagnostics.
public struct TelemetryEvent: Sendable, Equatable {
    public var name: String
    public var attributes: [String: String]
    public var timestamp: Date
    public init(name: String, attributes: [String: String] = [:], timestamp: Date = Date()) {
        self.name = name
        self.attributes = attributes
        self.timestamp = timestamp
    }
}

/// Policy decision envelope used to surface gateway persona outcomes to clients.
public enum PolicyDecision: String, Sendable, Equatable {
    case allow
    case deny
    case escalate
}

