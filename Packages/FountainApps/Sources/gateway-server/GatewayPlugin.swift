import Foundation
import FountainRuntime

/// Protocol describing middleware hooks for the gateway server.
public protocol GatewayPlugin: Sendable {
    /// Allows mutation or inspection of a request before routing.
    func prepare(_ request: HTTPRequest) async throws -> HTTPRequest
    /// Allows mutation or inspection of the response before it is returned.
    func respond(_ response: HTTPResponse, for request: HTTPRequest) async throws -> HTTPResponse
}

public extension GatewayPlugin {
    /// Default no-op implementation for request preparation.
    /// - Parameter request: Incoming request passed to the plugin.
    /// - Returns: The unmodified request for continued processing.
    func prepare(_ request: HTTPRequest) async throws -> HTTPRequest { request }
    /// Default no-op implementation for response processing.
    /// - Parameters:
    ///   - response: Response produced by subsequent handlers.
    ///   - request: Original request that generated the response.
    /// - Returns: The response passed through unchanged.
    func respond(_ response: HTTPResponse, for request: HTTPRequest) async throws -> HTTPResponse { response }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
