import Foundation
import FountainAIAdapters
import FountainStoreClient

public struct EngraverStudioConfiguration {
    public let gatewayURL: URL
    public let bearerToken: String?
    public let corpusId: String
    public let collection: String
    public let systemPrompts: [String]
    public let availableModels: [String]
    public let defaultModel: String
    public let persistenceStore: FountainStoreClient?
    public let debugEnabled: Bool

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let urlString = environment["FOUNTAIN_GATEWAY_URL"], let url = URL(string: urlString) {
            self.gatewayURL = url
        } else {
            self.gatewayURL = URL(string: "http://127.0.0.1:8080")!
        }

        self.bearerToken = environment["GATEWAY_BEARER"] ??
            environment["GATEWAY_JWT"] ??
            environment["FOUNTAIN_GATEWAY_BEARER"]

        self.corpusId = environment["ENGRAVER_CORPUS_ID"] ?? "engraver-space"
        self.collection = environment["ENGRAVER_COLLECTION"] ?? "chat-turns"

        let systemPrompt = environment["ENGRAVER_SYSTEM_PROMPT"] ??
            "You are the Engraver inside Fountain Studio. Maintain semantic memory across turns and cite corpora where relevant."
        self.systemPrompts = [systemPrompt]

        if let modelsEnv = environment["ENGRAVER_MODELS"] {
            let parsed = modelsEnv
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            self.availableModels = parsed.isEmpty ? ["gpt-4o-mini", "gpt-4o"] : parsed
        } else {
            self.availableModels = ["gpt-4o-mini", "gpt-4o"]
        }
        self.defaultModel = environment["ENGRAVER_DEFAULT_MODEL"] ?? availableModels.first ?? "gpt-4o-mini"

        if let disable = environment["ENGRAVER_DISABLE_PERSISTENCE"], disable.lowercased() == "true" {
            self.persistenceStore = nil
        } else {
            // Default to the in-memory implementation so the Studio works out of the box.
            self.persistenceStore = FountainStoreClient(client: EmbeddedFountainStoreClient())
        }

        if let flag = environment["ENGRAVER_DEBUG"]?.lowercased() {
            self.debugEnabled = (flag == "1" || flag == "true" || flag == "yes")
        } else {
            self.debugEnabled = false
        }
    }

    public func tokenProvider() -> GatewayChatClient.TokenProvider {
        let token = bearerToken
        return { token }
    }
}
