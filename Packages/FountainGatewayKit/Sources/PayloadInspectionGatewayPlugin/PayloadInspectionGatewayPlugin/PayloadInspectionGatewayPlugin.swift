import Foundation
import FountainRuntime

/// Plugin providing payload inspection capabilities for the gateway.
public struct PayloadInspectionGatewayPlugin: Sendable {
    public let router: Router
    private let handlers: Handlers

    /// Creates a new plugin instance.
    /// - Parameter maxPayloadBytes: Maximum payload size accepted by the inspector.
    public init(maxPayloadBytes: Int = 1024) {
        let h = Handlers(maxSize: maxPayloadBytes)
        self.handlers = h
        self.router = Router(handlers: h)
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
