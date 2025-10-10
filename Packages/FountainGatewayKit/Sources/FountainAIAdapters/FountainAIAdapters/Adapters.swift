import Foundation
import FountainAICore
import LLMGatewayAPI
import OpenAPIURLSession
import SemanticBrowserAPI
import PersistAPI

public final class LLMGatewayAdapter: LLMService {
    private let client: LLMGatewayAPI.Client
    public init(baseURL: URL, bearerToken: String? = nil) {
        let transport = OpenAPIURLSession.URLSessionTransport()
        self.client = LLMGatewayAPI.Client(serverURL: baseURL, transport: transport)
        self.bearerToken = bearerToken
    }
    private let bearerToken: String?

    public func chat(model: String, messages: [FountainAICore.ChatMessage]) async throws -> String {
        // Map to generated types
        let msgs: [Components.Schemas.MessageObject] = messages.map { .init(role: $0.role.rawValue, content: $0.content) }
        let body = Components.Schemas.ChatRequest(model: model, messages: msgs, functions: nil, function_call: nil)
        var headers = Operations.chatWithObjective.Input.Headers()
        if let token = bearerToken { headers.authorization = "Bearer \(token)" }
        let out = try await client.chatWithObjective(.init(headers: headers, body: .json(body)))
        switch out {
        case .ok(let ok):
            if case let .json(obj) = ok.body {
                // Best-effort extract text/answer from arbitrary JSON
                if let any = try? obj.get(), let dict = any as? [String: Any] {
                    if let s = dict["answer"] as? String { return s }
                    if let s = dict["text"] as? String { return s }
                    return String(describing: dict)
                }
                return "{}"
            }
            return ""
        default:
            return ""
        }
    }
}

public final class SemanticBrowserAdapter: BrowserService {
    private let client: SemanticBrowserClient
    public init(client: SemanticBrowserClient) { self.client = client }
    public func analyze(url: String, corpusId: String?) async throws -> (title: String?, summary: String?) {
        return try await client.browse(url: url, corpusId: corpusId)
    }
}

public final class PersistReflectionsAdapter: PersistenceService {
    private let client: PersistClient
    public init(client: PersistClient) { self.client = client }
    public func save(question: String, url: String?, answer: String, sourceURL: String?, sourceTitle: String?, corpusId: String?) async throws {
        guard let corpusId = corpusId else { return }
        let meta: [String: Any?] = ["sourceURL": sourceURL, "sourceTitle": sourceTitle, "asked": ISO8601DateFormatter().string(from: Date())]
        let metaText: String
        if let data = try? JSONSerialization.data(withJSONObject: meta.compactMapValues { $0 }, options: [.sortedKeys]) {
            metaText = String(data: data, encoding: .utf8) ?? "{}"
        } else { metaText = "{}" }
        let refl = Reflection(reflectionId: UUID().uuidString, corpusId: corpusId, question: question + (url == nil ? "" : "\nURL: \(url!)"), content: answer + "\n\n" + metaText)
        _ = try await client.addReflection(corpusId: corpusId, reflection: refl)
    }
}
