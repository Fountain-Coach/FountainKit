import Foundation
import FountainRuntime

/// Skeleton policy plugin that currently allows all requests.
/// This placeholder will be extended to consult persona decisions.
public struct PolicyGatewayPlugin: Sendable {
    public enum Mode: String, Sendable { case allowAll, persona }
    private let mode: Mode

    public init(mode: Mode = .allowAll) {
        self.mode = mode
    }

    // Future: expose evaluation entrypoints and metrics
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.

