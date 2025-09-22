import Foundation

public protocol SettingsStore {
    func load() throws -> AppSettings
    func save(_ settings: AppSettings) throws
}

public struct DefaultSettingsStore: SettingsStore {
    private let defaults: UserDefaults
    private let defaultsKey = "FountainAI.AppSettings"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() throws -> AppSettings {
        if let data = defaults.data(forKey: defaultsKey) {
            let dec = JSONDecoder()
            if let s = try? dec.decode(AppSettingsDTO.self, from: data) {
                return s.asDomain
            }
        }
        return AppSettings()
    }

    public func save(_ settings: AppSettings) throws {
        let issues = settings.validate()
        guard issues.isEmpty else { throw SettingsError.validationFailed(issues) }
        let dto = AppSettingsDTO.fromDomain(settings)
        let data = try JSONEncoder().encode(dto)
        defaults.set(data, forKey: defaultsKey)
    }
}

public enum SettingsError: Error, Equatable {
    case validationFailed([String])
}

// MARK: - Codable DTOs for persistence

private struct AppSettingsDTO: Codable {
    var provider: String
    var modelName: String
    var baseURL: String?
    var apiKeyRef: String?
    var persist: PersistDTO
    var corpusId: String

    var asDomain: AppSettings {
        AppSettings(
            provider: ModelProvider(rawValue: provider) ?? .openai,
            modelName: modelName,
            baseURL: baseURL,
            apiKeyRef: apiKeyRef,
            persist: persist.asDomain,
            corpusId: corpusId
        )
    }

    static func fromDomain(_ s: AppSettings) -> AppSettingsDTO {
        .init(
            provider: s.provider.rawValue,
            modelName: s.modelName,
            baseURL: s.baseURL,
            apiKeyRef: s.apiKeyRef,
            persist: PersistDTO.fromDomain(s.persist),
            corpusId: s.corpusId
        )
    }
}

private enum PersistDTO: Codable {
    case embedded(path: String)
    case remote(url: String, apiKeyRef: String?)

    var asDomain: PersistMode {
        switch self {
        case .embedded(let p): return .embedded(path: p)
        case .remote(let u, let k): return .remote(url: u, apiKeyRef: k)
        }
    }

    static func fromDomain(_ p: PersistMode) -> PersistDTO {
        switch p {
        case .embedded(let path): return .embedded(path: path)
        case .remote(let url, let k): return .remote(url: url, apiKeyRef: k)
        }
    }
}
