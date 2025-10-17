import Foundation
import Yams
import FountainStoreClient

/// Configuration for the gateway server.
public struct GatewayConfig: Codable {
    /// Default per-client limit when routes omit an explicit value.
    public var rateLimitPerMinute: Int

    public init(rateLimitPerMinute: Int = 60) {
        self.rateLimitPerMinute = rateLimitPerMinute
    }
}

/// Loads gateway configuration from FountainStore's `config/gateway.yml`.
/// Falls back to `Configuration/gateway.yml` when FountainStore is unavailable.
public func loadGatewayConfig(store: ConfigurationStore? = nil,
                              environment: [String: String] = ProcessInfo.processInfo.environment) throws -> GatewayConfig {
    // Highest priority: environment override for fast local control
    if let raw = environment["GATEWAY_RATE_LIMIT_PER_MINUTE"], let val = Int(raw) {
        return GatewayConfig(rateLimitPerMinute: val)
    }
    let svc = store ?? ConfigurationStore.fromEnvironment(environment)
    if let data = svc?.getSync("gateway.yml"), let text = String(data: data, encoding: .utf8) {
        return try decodeGatewayConfig(from: text)
    }
    let path = environment["GATEWAY_CONFIG_PATH"] ?? "Configuration/gateway.yml"
    let raw = try String(contentsOfFile: path, encoding: .utf8)
    return try decodeGatewayConfig(from: raw)
}

private func decodeGatewayConfig(from raw: String) throws -> GatewayConfig {
    let sanitized = raw
        .split(separator: "\n", omittingEmptySubsequences: false)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("©") }
        .joined(separator: "\n")
    let yaml = try Yams.load(yaml: sanitized) as? [String: Any] ?? [:]
    let defaults: [String: Any] = ["rateLimitPerMinute": 60]
    let merged = defaults.merging(yaml) { _, new in new }
    let data = try JSONSerialization.data(withJSONObject: merged)
    return try JSONDecoder().decode(GatewayConfig.self, from: data)
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
