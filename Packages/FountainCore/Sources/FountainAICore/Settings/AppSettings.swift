import Foundation

public enum ModelProvider: String, Sendable, Equatable { case openai, customHTTP, localServer }
public enum PersistMode: Sendable, Equatable {
    case embedded(path: String)
    case remote(url: String, apiKeyRef: String?)
}

public struct AppSettings: Sendable, Equatable {
    public var provider: ModelProvider
    public var modelName: String
    public var baseURL: String? // for custom/local
    public var apiKeyRef: String? // keychain reference name (not the secret)
    public var persist: PersistMode
    public var corpusId: String

    public init(provider: ModelProvider = .openai,
                modelName: String = "gpt-4o-mini",
                baseURL: String? = nil,
                apiKeyRef: String? = nil,
                persist: PersistMode = .embedded(path: "~/Library/Application Support/FountainAI"),
                corpusId: String = "default") {
        self.provider = provider
        self.modelName = modelName
        self.baseURL = baseURL
        self.apiKeyRef = apiKeyRef
        self.persist = persist
        self.corpusId = corpusId
    }

    public func validate() -> [String] {
        var issues: [String] = []
        if modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Model name must not be empty") }
        switch provider {
        case .openai:
            if apiKeyRef == nil { issues.append("OpenAI requires an API key (stored in Keychain)") }
        case .customHTTP, .localServer:
            if (baseURL?.isEmpty ?? true) { issues.append("Base URL required for custom/local provider") }
        }
        switch persist {
        case .embedded(let path):
            if path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Embedded path must not be empty") }
        case .remote(let url, _):
            if url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Persist URL must not be empty") }
        }
        if corpusId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Corpus ID must not be empty") }
        return issues
    }
}
