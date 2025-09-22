import Foundation
import FountainRuntime

/// Minimal router for LLM gateway endpoints.
public struct Router: Sendable {
    public var handlers: Handlers
    public init(handlers: Handlers = Handlers()) {
        self.handlers = handlers
    }

    /// Routes requests to the appropriate handler.
    /// - Parameter request: Incoming HTTP request.
    /// - Returns: A response if a matching route is found, otherwise `nil`.
    public func route(_ request: HTTPRequest) async throws -> HTTPResponse? {
        switch (request.method, request.path.split(separator: "/", omittingEmptySubsequences: true)) {
        case ("GET", ["metrics"]):
            return await handlers.metrics_metrics_get()
        case ("POST", ["chat"]):
            if let body = try? JSONDecoder().decode(ChatRequest.self, from: request.body) {
                return try await handlers.chatWithObjective(request, body: body)
            }
            return HTTPResponse(status: 400)
        default:
            return nil
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
