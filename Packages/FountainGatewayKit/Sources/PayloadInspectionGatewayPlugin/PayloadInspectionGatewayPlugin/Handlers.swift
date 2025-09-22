import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FountainRuntime

/// Actor housing payload inspection handlers backed by an LLM.
public actor Handlers {
    private let client = LLMPluginClient(personaPath: "openapi/personas/payload-inspection.md")
    private let maxSize: Int

    public init(maxSize: Int = 1024) {
        self.maxSize = maxSize
    }

    /// Delegates payload inspection to the LLM.
    public func inspectPayload(_ request: HTTPRequest, body: PayloadInspectionRequest?) async throws -> HTTPResponse {
        guard let body = body else {
            return HTTPResponse(status: 400)
        }
        guard body.payload.utf8.count <= maxSize else {
            return HTTPResponse(status: 413)
        }
        let prompt = (try? String(data: JSONEncoder().encode(body), encoding: .utf8)) ?? ""
        let result = (try? await client.call(prompt: prompt)) ?? "{}"
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: Data(result.utf8))
    }
}

/// Minimal client that forwards prompts and persona to the LLM Gateway.
struct LLMPluginClient {
    let persona: String
    let url: URL

    init(personaPath: String,
         url: URL = URL(string: ProcessInfo.processInfo.environment["LLM_GATEWAY_URL"] ?? "http://localhost:8080/chat")!) {
        self.persona = (try? String(contentsOfFile: personaPath, encoding: .utf8)) ?? ""
        self.url = url
    }

    func call(prompt: String) async throws -> String {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ["persona": persona, "prompt": prompt]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: req)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
