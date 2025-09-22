import Foundation
import FountainRuntime
import protocol SecuritySentinelGatewayPlugin.SecuritySentinelClient
import enum SecuritySentinelGatewayPlugin.SentinelClientFactory
import struct DestructiveGuardianGatewayPlugin.Handlers
import struct DestructiveGuardianGatewayPlugin.GuardianEvaluateRequest
import struct DestructiveGuardianGatewayPlugin.GuardianEvaluateResponse

/// High level verdict returned by a persona evaluation.
public enum GatewayPersonaVerdict: Sendable {
    /// Request is permitted.
    case allow
    /// Request is rejected with a reason and the persona responsible.
    case deny(reason: String, persona: String)
    /// Persona cannot authorise the request and requires escalation.
    case escalate(reason: String, persona: String)
}

/// Abstraction for individual personas participating in gateway decisions.
public protocol GatewayPersona: Sendable {
    /// Human readable identifier for the persona.
    var name: String { get }
    /// Evaluate a request and return a verdict.
    func evaluate(_ request: HTTPRequest) async -> GatewayPersonaVerdict
}

/// Coordinates multiple personas and produces a combined decision.
public struct GatewayPersonaOrchestrator: Sendable {
    /// Personas consulted in sequence for each request.
    public let personas: [GatewayPersona]

    public init(personas: [GatewayPersona]) {
        self.personas = personas
    }

    /// Consults all personas in order and merges their decisions.
    /// - Parameter request: Incoming HTTP request under evaluation.
    /// - Returns: The final verdict after consulting all personas.
    public func decide(for request: HTTPRequest) async -> GatewayPersonaVerdict {
        var escalation: (String, String)?
        for persona in personas {
            let verdict = await persona.evaluate(request)
            switch verdict {
            case .allow:
                continue
            case .deny:
                return verdict
            case .escalate(let reason, let name):
                if escalation == nil { escalation = (reason, name) }
            }
        }
        if let esc = escalation {
            return .escalate(reason: esc.0, persona: esc.1)
        }
        return .allow
    }
}

/// Baseline system persona description outlining collaboration rules.
public let baselineSystemPersona: String = """
You are the Gateway Persona Orchestrator. Coordinate specialised personas such as
SecuritySentinel and DestructiveGuardian. Each persona independently evaluates
incoming requests and returns *allow*, *deny* or *escalate*. A single *deny*
from any persona yields an overall denial. If no persona denies but at least one
escalates, return an *escalate* decision. Only if all personas allow may the
request proceed.
"""

// MARK: - Built-in Personas

/// Persona backed by the Security Sentinel service.
public struct SecuritySentinelPersona: GatewayPersona {
    public let client: SecuritySentinelClient
    public var name: String { "SecuritySentinel" }

    public init(client: SecuritySentinelClient = SentinelClientFactory.make()) {
        self.client = client
    }

    public func evaluate(_ request: HTTPRequest) async -> GatewayPersonaVerdict {
        let summary = "\(request.method) \(request.path)"
        do {
            let decision = try await client.consult(summary: summary, context: nil)
            switch decision.decision {
            case .allow:
                return .allow
            case .deny:
                return .deny(reason: decision.reason, persona: name)
            case .escalate:
                return .escalate(reason: decision.reason, persona: name)
            }
        } catch {
            return .escalate(reason: "error: \(error)", persona: name)
        }
    }
}

/// Abstraction over types capable of performing destructive guardian evaluations.
public protocol GuardianEvaluating: Sendable {
    func guardianEvaluate(_ request: HTTPRequest, body: GuardianEvaluateRequest?) async throws -> HTTPResponse
}

extension Handlers: GuardianEvaluating {}

/// Persona enforcing destructive operation policies.
public struct DestructiveGuardianPersona: GatewayPersona {
    private let handler: any GuardianEvaluating
    public var name: String { "DestructiveGuardian" }

    public init(sensitivePaths: [String] = ["/"],
                privilegedTokens: [String] = [],
                auditURL: URL = URL(fileURLWithPath: "logs/guardian.log")) {
        self.handler = Handlers(
            sensitivePaths: sensitivePaths,
            privilegedTokens: Set(privilegedTokens),
            auditURL: auditURL
        )
    }

    public init(handler: any GuardianEvaluating) {
        self.handler = handler
    }

    public func evaluate(_ request: HTTPRequest) async -> GatewayPersonaVerdict {
        let body = GuardianEvaluateRequest(method: request.method,
                                           path: request.path,
                                           manualApproval: false,
                                           serviceToken: nil)
        do {
            let resp = try await handler.guardianEvaluate(request, body: body)
            if let decision = try? JSONDecoder().decode(GuardianEvaluateResponse.self, from: resp.body) {
                if decision.decision.lowercased() == "allow" {
                    return .allow
                } else {
                    return .deny(reason: "guardian", persona: name)
                }
            }
            return .escalate(reason: "invalid response", persona: name)
        } catch {
            return .escalate(reason: "error: \(error)", persona: name)
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
