import Foundation

public struct HTTPKernel {
    let router: Router

    public init(handlers: Handlers = Handlers()) {
        self.router = Router(handlers: handlers)
    }

    public func handle(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await router.route(request)
    }
}

extension HTTPKernel: @unchecked Sendable {}
// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
