import Foundation
import FountainStoreClient
import FountainStore

/// Minimal async HTTP router used by lightweight servers.
public struct HTTPKernel: @unchecked Sendable {
    /// Closure that transforms a ``HTTPRequest`` into an ``HTTPResponse``.
    let router: (HTTPRequest) async throws -> HTTPResponse

    /// Creates a new kernel with the given routing closure.
    /// - Parameter route: Handler responsible for processing requests.
    public init(route: @escaping (HTTPRequest) async throws -> HTTPResponse) {
        self.router = route
    }

    /// Passes a request through the router and returns the response.
    /// - Parameter request: Incoming request object.
    /// - Throws: Rethrows any error produced by the routing closure.
    public func handle(_ request: HTTPRequest) async throws -> HTTPResponse {
        do {
            return try await router(request)
        } catch PersistenceError.notSupported(let need) {
            let body = (try? JSONEncoder().encode(["error": "not-supported", "need": need])) ?? Data()
            return HTTPResponse(status: 400, headers: ["Content-Type": "application/json"], body: body)
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
