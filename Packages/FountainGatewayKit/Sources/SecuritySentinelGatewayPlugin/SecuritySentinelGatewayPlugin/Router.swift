import Foundation
import FountainRuntime

/// Routes Security Sentinel consult requests.
public struct Router: Sendable {
    public var handlers: Handlers
    public init(handlers: Handlers = Handlers()) { self.handlers = handlers }

    public func route(_ request: HTTPRequest) async throws -> HTTPResponse? {
        switch (request.method, request.path) {
        case ("POST", "/sentinel/consult"):
            if let body = try? JSONDecoder().decode(ConsultRequest.self, from: request.body) {
                do {
                    try body.validate()
                } catch {
                    return HTTPResponse(status: 400)
                }
                return try await handlers.sentinelConsult(request, body: body)
            } else {
                return HTTPResponse(status: 400)
            }
        default:
            return nil
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
