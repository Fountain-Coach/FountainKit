import Foundation
import FountainAICore
import LLMGatewayAPI
import SemanticBrowserAPI
import PersistAPI

public final class LLMGatewayAdapter: LLMService {
    private let client: LLMGatewayClient
    public init(client: LLMGatewayClient) { self.client = client }
    public func chat(model: String, messages: [FountainAICore.ChatMessage]) async throws -> String {
        let req = ChatRequest(model: model, messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) })
        let json = try await client.chat(req)
        // best-effort: extract a text field
        switch json {
        case .string(let s): return s
        case .object(let o):
            if case let .string(s)? = o["answer"] { return s }
            if case let .string(s)? = o["text"] { return s }
            return String(describing: o)
        default: return String(describing: json)
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
