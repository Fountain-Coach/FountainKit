import Foundation
import Crypto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Error thrown when authorization fails.
public struct UnauthorizedError: Error {}

/// Error thrown when authorization is denied for insufficient scope or role.
public struct ForbiddenError: Error {}

/// Claims extracted from a validated access token.
public struct TokenClaims: Sendable {
    /// Optional role claim.
    public let role: String?
    /// Scopes granted to the token.
    public let scopes: [String]
}

/// Protocol for pluggable token validation strategies.
public protocol TokenValidator: Sendable {
    /// Validates the token and returns extracted claims when valid.
    func validate(token: String) async -> TokenClaims?
}

/// Provides a symmetric key for HS256 verification.
public protocol KeyProvider: Sendable {
    func symmetricKey() -> SymmetricKey
}

/// Default key provider using `GATEWAY_JWT_SECRET`.
public struct EnvKeyProvider: KeyProvider {
    private let secret: String
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.secret = environment["GATEWAY_JWT_SECRET"] ?? "secret"
    }
    public func symmetricKey() -> SymmetricKey { SymmetricKey(data: Data(secret.utf8)) }
}

/// Key provider that fetches a JWKS (JSON Web Key Set) and uses the first symmetric (oct) key.
/// Note: RS256 keys are not yet supported here; this provider targets HS256 via "kty":"oct".
public final class JWKSKeyProvider: @unchecked Sendable, KeyProvider {
    private var key: SymmetricKey
    private let url: URL
    private let session: URLSession
    public init?(jwksURL: String, session: URLSession = .shared) {
        guard let u = URL(string: jwksURL) else { return nil }
        self.url = u
        self.session = session
        self.key = SymmetricKey(data: Data())
        // Best-effort fetch at init; failures will keep an empty key which will fail validation.
        Task.detached { [weak self] in await self?.refresh() }
    }
    public func symmetricKey() -> SymmetricKey { key }
    public func refresh() async {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        do {
            let (data, resp) = try await session.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let keys = obj["keys"] as? [[String: Any]] {
                // Pick first symmetric (oct) key
                for k in keys {
                    if let kty = k["kty"] as? String, kty.uppercased() == "OCT", let kval = k["k"] as? String, let raw = Data(base64URLEncoded: kval) {
                        self.key = SymmetricKey(data: raw)
                        break
                    }
                }
            }
        } catch {
            // ignore
        }
    }
}

/// HMAC (HS256) validator using a pluggable ``KeyProvider`` and claim options.
public struct HMACKeyValidator: TokenValidator {
    private let keyProvider: KeyProvider
    private let options: JWTValidationOptions
    public init(keyProvider: KeyProvider = EnvKeyProvider(), options: JWTValidationOptions = JWTValidationOptions()) {
        self.keyProvider = keyProvider
        self.options = options
    }
    public func validate(token: String) async -> TokenClaims? {
        guard let payload = CredentialStoreValidator.verifyAndDecode(token: token, key: keyProvider.symmetricKey(), options: options) else { return nil }
        let scopes = payload.role.map { [$0] } ?? []
        return TokenClaims(role: payload.role, scopes: scopes)
    }
}

/// Validation options for JWT claims.
public struct JWTValidationOptions: Sendable {
    public let issuer: String?
    public let audience: String?
    public let leewaySeconds: Int
    public let requireJTI: Bool
    public init(issuer: String? = ProcessInfo.processInfo.environment["GATEWAY_JWT_ISS"],
                audience: String? = ProcessInfo.processInfo.environment["GATEWAY_JWT_AUD"],
                leewaySeconds: Int = Int(ProcessInfo.processInfo.environment["GATEWAY_JWT_LEEWAY"] ?? "60") ?? 60,
                requireJTI: Bool = (ProcessInfo.processInfo.environment["GATEWAY_JWT_REQUIRE_JTI"] as NSString?)?.boolValue ?? false) {
        self.issuer = issuer
        self.audience = audience
        self.leewaySeconds = leewaySeconds
        self.requireJTI = requireJTI
    }
}

/// Default validator backed by ``CredentialStore``.
public struct CredentialStoreValidator: TokenValidator {
    private let keyProvider: KeyProvider
    private let options: JWTValidationOptions
    public init(keyProvider: KeyProvider = EnvKeyProvider(), options: JWTValidationOptions = JWTValidationOptions()) {
        self.keyProvider = keyProvider
        self.options = options
    }
    public func validate(token: String) async -> TokenClaims? {
        guard let payload = Self.verifyAndDecode(token: token, key: keyProvider.symmetricKey(), options: options) else { return nil }
        let scopes = payload.role.map { [$0] } ?? []
        return TokenClaims(role: payload.role, scopes: scopes)
    }

    struct JWTPayload: Decodable { let iss: String?; let aud: String?; let sub: String?; let exp: Int; let nbf: Int?; let iat: Int?; let jti: String?; let role: String? }

    static func verifyAndDecode(token: String, key: SymmetricKey, options: JWTValidationOptions) -> JWTPayload? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        let headerPayload = parts[0] + "." + parts[1]
        guard let sig = Data(base64URLEncoded: String(parts[2])) else { return nil }
        let expected = HMAC<SHA256>.authenticationCode(for: Data(headerPayload.utf8), using: key)
        guard Data(expected) == sig else { return nil }
        guard let payloadData = Data(base64URLEncoded: String(parts[1])),
              let payload = try? JSONDecoder().decode(JWTPayload.self, from: payloadData) else { return nil }
        let now = Int(Date().timeIntervalSince1970)
        // exp with leeway
        guard payload.exp + options.leewaySeconds >= now else { return nil }
        // nbf with leeway
        if let nbf = payload.nbf, nbf - options.leewaySeconds > now { return nil }
        // iss/aud checks if provided
        if let iss = options.issuer, payload.iss != iss { return nil }
        if let aud = options.audience, payload.aud != aud { return nil }
        if options.requireJTI && (payload.jti ?? "").isEmpty { return nil }
        return payload
    }
}

/// Validator delegating to an OAuth2 introspection endpoint.
public struct OAuth2Validator: TokenValidator {
    private let introspectionURL: URL
    private let clientId: String?
    private let clientSecret: String?
    private let session: URLSession
    public init(introspectionURL: URL,
                clientId: String? = nil,
                clientSecret: String? = nil,
                session: URLSession = .shared) {
        self.introspectionURL = introspectionURL
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.session = session
    }
    public init?(environment: [String: String] = ProcessInfo.processInfo.environment, session: URLSession = .shared) {
        guard let urlStr = environment["GATEWAY_OAUTH2_INTROSPECTION_URL"],
              let url = URL(string: urlStr) else { return nil }
        let id = environment["GATEWAY_OAUTH2_CLIENT_ID"]
        let secret = environment["GATEWAY_OAUTH2_CLIENT_SECRET"]
        self.init(introspectionURL: url, clientId: id, clientSecret: secret, session: session)
    }
    public func validate(token: String) async -> TokenClaims? {
        var request = URLRequest(url: introspectionURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "token=\(token)".data(using: .utf8)
        if let id = clientId, let secret = clientSecret {
            let creds = "\(id):\(secret)".data(using: .utf8)!
            let auth = creds.base64EncodedString()
            request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, resp) = try await session.data(for: request)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            struct IntrospectionResponse: Decodable {
                let active: Bool
                let scope: String?
                let role: String?
            }
            let result = try JSONDecoder().decode(IntrospectionResponse.self, from: data)
            guard result.active else { return nil }
            let scopes = result.scope?.split(separator: " ").map(String.init) ?? []
            return TokenClaims(role: result.role, scopes: scopes)
        } catch {
            return nil
        }
    }
}

private extension Data {
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
