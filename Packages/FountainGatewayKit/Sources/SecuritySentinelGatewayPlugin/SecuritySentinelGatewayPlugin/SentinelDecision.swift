import Foundation

/// Origin of a decision returned by the Security Sentinel.
public enum SentinelSource: String, Codable, Sendable {
    /// Decision produced by a large language model backed sentinel service.
    case llm
    /// Decision produced by local fallback rules.
    case fallback_rules
}

/// High level verdict returned by the Security Sentinel.
public enum SentinelVerdict: String, Codable, Sendable {
    /// Operation is permitted.
    case allow
    /// Operation is rejected.
    case deny
    /// Operation requires escalation or manual approval.
    case escalate
}

/// Normalised decision payload produced by the Security Sentinel service.
public struct SentinelDecision: Codable, Sendable {
    /// Final verdict such as allow, deny or escalate.
    public let decision: SentinelVerdict
    /// Human readable explanation of the verdict.
    public let reason: String
    /// Optional confidence score from the model.
    public let confidence: Double?
    /// Identifier of the model that produced the decision, if available.
    public let model: String?
    /// Identifier for tracking this consult request.
    public let requestID: String
    /// Latency in milliseconds for generating the response.
    public let latencyMS: Int
    /// Source system that produced the verdict.
    public let source: SentinelSource
    /// RFC3339 timestamp when the decision was produced.
    public let timestamp: String

    public init(
        decision: SentinelVerdict,
        reason: String,
        confidence: Double?,
        model: String?,
        requestID: String,
        latencyMS: Int,
        source: SentinelSource,
        timestamp: String
    ) {
        self.decision = decision
        self.reason = reason
        self.confidence = confidence
        self.model = model
        self.requestID = requestID
        self.latencyMS = latencyMS
        self.source = source
        self.timestamp = timestamp
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
