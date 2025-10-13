import Foundation
import FountainAIAdapters
import FountainStoreClient

public struct EngraverStudioConfiguration: Sendable {
    public let gatewayURL: URL
    public let bearerToken: String?
    public let corpusId: String
    public let collection: String
    public let systemPrompts: [String]
    public let availableModels: [String]
    public let defaultModel: String
    public let persistenceStore: FountainStoreClient?
    public let debugEnabled: Bool
    public let awarenessBaseURL: URL?

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        var env = environment

        if (env["GATEWAY_BEARER"]?.isEmpty ?? true),
           let secret = SecretStoreHelper.read(service: "FountainAI", account: "GATEWAY_BEARER") {
            env["GATEWAY_BEARER"] = secret
        }
        if (env["OPENAI_API_KEY"]?.isEmpty ?? true),
           let apiKey = SecretStoreHelper.read(service: "FountainAI", account: "OPENAI_API_KEY") {
            env["OPENAI_API_KEY"] = apiKey
        }

        if let urlString = env["FOUNTAIN_GATEWAY_URL"], let url = URL(string: urlString) {
            self.gatewayURL = url
        } else {
            self.gatewayURL = URL(string: "http://127.0.0.1:8010")!
        }

        self.bearerToken = env["GATEWAY_BEARER"] ??
            env["GATEWAY_JWT"] ??
            env["FOUNTAIN_GATEWAY_BEARER"]

        self.corpusId = env["ENGRAVER_CORPUS_ID"] ?? "engraver-space"
        self.collection = env["ENGRAVER_COLLECTION"] ?? "chat-turns"

        let systemPrompt = env["ENGRAVER_SYSTEM_PROMPT"] ??
            "You are the Engraver inside Fountain Studio. Maintain semantic memory across turns and cite corpora where relevant."
        self.systemPrompts = [systemPrompt]

        if let modelsEnv = env["ENGRAVER_MODELS"] {
            let parsed = modelsEnv
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            self.availableModels = parsed.isEmpty ? ["gpt-4o-mini", "gpt-4o"] : parsed
        } else {
            self.availableModels = ["gpt-4o-mini", "gpt-4o"]
        }
        self.defaultModel = env["ENGRAVER_DEFAULT_MODEL"] ?? availableModels.first ?? "gpt-4o-mini"

        if let disable = env["ENGRAVER_DISABLE_PERSISTENCE"], disable.lowercased() == "true" {
            self.persistenceStore = nil
        } else {
            let storeURL = Self.resolveStoreDirectory(from: env)
            if let diskClient = try? DiskFountainStoreClient(rootDirectory: storeURL) {
                self.persistenceStore = FountainStoreClient(client: diskClient)
            } else {
                self.persistenceStore = FountainStoreClient(client: EmbeddedFountainStoreClient())
            }
        }

        if let flag = env["ENGRAVER_DEBUG"]?.lowercased() {
            self.debugEnabled = (flag == "1" || flag == "true" || flag == "yes")
        } else {
            self.debugEnabled = false
        }

        if let disableAwareness = env["ENGRAVER_DISABLE_AWARENESS"]?.lowercased(), disableAwareness == "true" {
            self.awarenessBaseURL = nil
        } else {
            self.awarenessBaseURL = Self.resolveAwarenessURL(from: env)
        }
    }

    public func tokenProvider() -> GatewayChatClient.TokenProvider {
        let token = bearerToken
        return { token }
    }
}

extension EngraverStudioConfiguration {
    private static func resolveStoreDirectory(from env: [String: String]) -> URL {
        let rawPath: String
        if let configured = env["ENGRAVER_STORE_PATH"], !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rawPath = configured
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return home
                .appendingPathComponent(".fountain", isDirectory: true)
                .appendingPathComponent("engraver-store", isDirectory: true)
        }

        let expanded: String
        if rawPath.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            expanded = home + rawPath.dropFirst()
        } else {
            expanded = rawPath
        }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    private static func resolveAwarenessURL(from env: [String: String]) -> URL? {
        if let raw = env["AWARENESS_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "http://127.0.0.1:8001")
    }
}
