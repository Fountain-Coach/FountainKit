import Foundation
import FountainRuntime

/// Collection of handlers for guardian evaluation.
public struct Handlers: Sendable {
    private let sensitivePaths: [String]
    private let privilegedTokens: Set<String>
    private let auditURL: URL

    public init(sensitivePaths: [String],
                privilegedTokens: Set<String>,
                auditURL: URL) {
        self.sensitivePaths = sensitivePaths
        self.privilegedTokens = privilegedTokens
        self.auditURL = auditURL
    }

    /// Evaluates a request and returns an allow/deny decision.
    public func guardianEvaluate(_ request: HTTPRequest, body: GuardianEvaluateRequest?) async throws -> HTTPResponse {
        guard let body else { return HTTPResponse(status: 400) }
        let protected = isProtected(method: body.method, path: body.path)
        let manual = body.manualApproval ?? false
        let tokenValid = body.serviceToken.map { privilegedTokens.contains($0) } ?? false
        let allowed: Bool
        let reason: String
        if protected {
            allowed = manual || tokenValid
            reason = manual ? "manual" : tokenValid ? "token" : "missing"
        } else {
            allowed = true
            reason = "unprotected"
        }
        log(method: body.method, path: body.path, allowed: allowed, reason: reason)
        let resp = GuardianEvaluateResponse(decision: allowed ? "allow" : "deny")
        let data = try JSONEncoder().encode(resp)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    private func isProtected(method: String, path: String) -> Bool {
        let m = method.uppercased()
        guard ["DELETE", "PUT", "PATCH"].contains(m) else { return false }
        return sensitivePaths.contains { path.hasPrefix($0) }
    }

    private func log(method: String, path: String, allowed: Bool, reason: String) {
        let line = "\(method) \(path) -> \(allowed ? "allow" : "deny") [\(reason)]\n"
        do {
            let dir = auditURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: auditURL.path) {
                _ = FileManager.default.createFile(atPath: auditURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: auditURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            // ignore audit logging errors
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
