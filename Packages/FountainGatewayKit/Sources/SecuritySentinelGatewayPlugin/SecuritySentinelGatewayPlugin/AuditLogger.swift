import Foundation
import Logging

enum AuditLogger {
    private static let logger = Logger(label: "security-sentinel-audit")

    static func logConsult(inputSummary: String, context: [String: String] = [:], decision: SentinelDecision) {
        let hashed = Hashing.sha256Hex(inputSummary)
        let redacted = redact(context)
        var payload: [String: Any] = [
            "requestID": decision.requestID,
            "decision": decision.decision.rawValue,
            "source": decision.source.rawValue,
            "latencyMS": decision.latencyMS,
            "hashedSummary": hashed
        ]
        if let model = decision.model {
            payload["model"] = model
        }
        if !redacted.isEmpty {
            payload["context"] = redacted
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let line = String(data: data, encoding: .utf8) {
            logger.info(Logger.Message(stringLiteral: line))
        }
    }

    static func redact(_ context: [String: String]) -> [String: String] {
        let sensitive = ["token", "apikey", "secret"]
        var result: [String: String] = [:]
        for (key, value) in context {
            if sensitive.contains(where: { key.lowercased().contains($0) }) {
                result[key] = "[REDACTED]"
            } else {
                result[key] = value
            }
        }
        return result
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
