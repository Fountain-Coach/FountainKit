import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FountainRuntime

/// Collection of handlers for auth gateway endpoints backed by an LLM.
public actor Handlers {
    private let client: LLMPluginClient

    public init(client: LLMPluginClient = LLMPluginClient(personaPath: "openapi/personas/auth.md")) {
        self.client = client
    }

    /// Delegates validation to the LLM using the Auth persona.
    public func authValidate(_ request: HTTPRequest, body: ValidateRequest?) async throws -> HTTPResponse {
        let prompt = body.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) } ?? ""
        let result = (try? await client.call(prompt: prompt)) ?? "{}"
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: Data(result.utf8))
    }

    /// Retrieves claims for the supplied token via the LLM.
    public func authClaims(_ request: HTTPRequest, body: NoBody?) async throws -> HTTPResponse {
        let token = request.headers["Authorization"] ?? ""
        let result = (try? await client.call(prompt: token)) ?? "{}"
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: Data(result.utf8))
    }
}

/// Minimal client that forwards prompts and persona to the LLM Gateway.
public struct LLMPluginClient: Sendable {
    public let persona: String
    public let url: URL
    public let session: URLSession

    public init(personaPath: String,
                url: URL = URL(string: ProcessInfo.processInfo.environment["LLM_GATEWAY_URL"] ?? "http://localhost:8080/chat")!,
                session: URLSession = .shared) {
        self.persona = (try? String(contentsOfFile: personaPath, encoding: .utf8)) ?? ""
        self.url = url
        self.session = session
    }

    public func call(prompt: String) async throws -> String {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ["persona": persona, "prompt": prompt]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await session.data(for: req)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
