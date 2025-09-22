import Foundation
import Crypto

/// Provides access to client credentials and JWT signing.
public struct CredentialStore: @unchecked Sendable {
    private let credentials: [String: String]
    private let roles: [String: String]
    private let signingKey: SymmetricKey

    /// Loads credentials and signing key from environment variables.
    /// Expected format for credentials: `GATEWAY_CRED_<CLIENT_ID>`.
    /// Signing key is read from `GATEWAY_JWT_SECRET`.
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        var credMap: [String: String] = [:]
        var roleMap: [String: String] = [:]
        for (key, value) in environment {
            if key.hasPrefix("GATEWAY_CRED_") {
                let id = String(key.dropFirst("GATEWAY_CRED_".count))
                credMap[id] = value
            } else if key.hasPrefix("GATEWAY_ROLE_") {
                let id = String(key.dropFirst("GATEWAY_ROLE_".count))
                roleMap[id] = value
            }
        }
        self.credentials = credMap
        self.roles = roleMap
        let secret = environment["GATEWAY_JWT_SECRET"] ?? "secret"
        self.signingKey = SymmetricKey(data: Data(secret.utf8))
    }

    /// Verifies a pair of client credentials against the store.
    public func validate(clientId: String, clientSecret: String) -> Bool {
        credentials[clientId] == clientSecret
    }

    /// Returns the configured role for a client identifier.
    public func role(forClientId id: String) -> String? {
        roles[id]
    }

    /// Generates a signed JWT for the given subject with an expiry.
    public func signJWT(subject: String, expiresAt: Date, role: String? = nil) throws -> String {
        let header = JWTHeader()
        let payload = JWTPayload(sub: subject, exp: Int(expiresAt.timeIntervalSince1970), role: role)
        let headerData = try JSONEncoder().encode(header)
        let payloadData = try JSONEncoder().encode(payload)
        let header64 = headerData.base64URLEncodedString()
        let payload64 = payloadData.base64URLEncodedString()
        let signingInput = "\(header64).\(payload64)"
        let signature = HMAC<SHA256>.authenticationCode(for: Data(signingInput.utf8), using: signingKey)
        let signature64 = Data(signature).base64URLEncodedString()
        return "\(signingInput).\(signature64)"
    }

    /// Validates a JWT signature and expiry.
    public func verify(jwt: String) -> Bool {
        let segments = jwt.split(separator: ".")
        guard segments.count == 3 else { return false }
        let signingInput = segments[0] + "." + segments[1]
        guard let signatureData = Data(base64URLEncoded: String(segments[2])) else { return false }
        let expected = HMAC<SHA256>.authenticationCode(for: Data(signingInput.utf8), using: signingKey)
        guard Data(expected) == signatureData else { return false }
        guard let payloadData = Data(base64URLEncoded: String(segments[1])),
              let payload = try? JSONDecoder().decode(JWTPayload.self, from: payloadData) else { return false }
        return payload.exp > Int(Date().timeIntervalSince1970)
    }

    /// Extracts the role claim from a verified JWT.
    public func role(for jwt: String) -> String? {
        let segments = jwt.split(separator: ".")
        guard segments.count == 3,
              let payloadData = Data(base64URLEncoded: String(segments[1])),
              let payload = try? JSONDecoder().decode(JWTPayload.self, from: payloadData) else { return nil }
        return payload.role
    }

    /// Extracts the subject claim from a verified JWT.
    public func subject(for jwt: String) -> String? {
        let segments = jwt.split(separator: ".")
        guard segments.count == 3,
              let payloadData = Data(base64URLEncoded: String(segments[1])),
              let payload = try? JSONDecoder().decode(JWTPayload.self, from: payloadData) else { return nil }
        return payload.sub
    }
}

private struct JWTHeader: Encodable { let alg = "HS256"; let typ = "JWT" }
private struct JWTPayload: Codable { let sub: String; let exp: Int; let role: String? }

private extension Data {
    func base64URLEncodedString() -> String {
        self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded input: String) {
        var base64 = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = 4 - base64.count % 4
        if padding < 4 { base64 += String(repeating: "=", count: padding) }
        guard let data = Data(base64Encoded: base64) else { return nil }
        self = data
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
