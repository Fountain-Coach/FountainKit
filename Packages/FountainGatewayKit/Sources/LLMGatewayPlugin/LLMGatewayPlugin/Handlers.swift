import Foundation
import FountainRuntime

/// Collection of request handlers used by ``LLMGatewayPlugin``.
public struct Handlers: Sendable {
    public init() {}

    /// Placeholder handler for ``POST /chat``.
    public func chatWithObjective(_ request: HTTPRequest, body: ChatRequest) async throws -> HTTPResponse {
        let id = UUID().uuidString
        let obj: [String: Any] = ["id": id]
        let data = try JSONSerialization.data(withJSONObject: obj)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    /// Prometheus style metrics endpoint.
    public func metrics_metrics_get() async -> HTTPResponse {
        let uptime = Int(ProcessInfo.processInfo.systemUptime)
        let body = Data("llm_gateway_uptime_seconds \(uptime)\n".utf8)
        return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: body)
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
