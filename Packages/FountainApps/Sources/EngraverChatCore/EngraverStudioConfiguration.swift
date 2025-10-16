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
    public let bootstrapBaseURL: URL?
    public let seedingConfiguration: SeedingConfiguration?
    public let fountainRepoRoot: URL?

    public struct SeedingConfiguration: Sendable {
        public struct Source: Sendable {
            public let name: String
            public let url: URL
            public let corpusId: String
            public let labels: [String]

            public init(name: String, url: URL, corpusId: String, labels: [String]) {
                self.name = name
                self.url = url
                self.corpusId = corpusId
                self.labels = labels
            }
        }

        public struct Browser: Sendable {
            public struct StoreOverride: Sendable {
                public let url: URL
                public let apiKey: String?
                public let timeoutMs: Int?

                public init(url: URL, apiKey: String?, timeoutMs: Int?) {
                    self.url = url
                    self.apiKey = apiKey
                    self.timeoutMs = timeoutMs
                }
            }

            public enum Mode: String, Sendable {
                case quick
                case standard
                case deep
            }

            public let baseURL: URL
            public let apiKey: String?
            public let mode: Mode
            public let defaultLabels: [String]
            public let pagesCollection: String?
            public let segmentsCollection: String?
            public let entitiesCollection: String?
            public let tablesCollection: String?
            public let storeOverride: StoreOverride?

            public init(
                baseURL: URL,
                apiKey: String?,
                mode: Mode,
                defaultLabels: [String],
                pagesCollection: String?,
                segmentsCollection: String?,
                entitiesCollection: String?,
                tablesCollection: String?,
                storeOverride: StoreOverride?
            ) {
                self.baseURL = baseURL
                self.apiKey = apiKey
                self.mode = mode
                self.defaultLabels = defaultLabels
                self.pagesCollection = pagesCollection
                self.segmentsCollection = segmentsCollection
                self.entitiesCollection = entitiesCollection
                self.tablesCollection = tablesCollection
                self.storeOverride = storeOverride
            }
        }

        public let sources: [Source]
        public let browser: Browser

        public init(sources: [Source], browser: Browser) {
            self.sources = sources
            self.browser = browser
        }
    }

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

        if let disableBootstrap = env["ENGRAVER_DISABLE_BOOTSTRAP"]?.lowercased(), disableBootstrap == "true" {
            self.bootstrapBaseURL = nil
        } else {
            self.bootstrapBaseURL = Self.resolveBootstrapURL(from: env)
        }

        self.seedingConfiguration = Self.resolveSeedingConfiguration(from: env)
        if let root = env["FOUNTAINKIT_ROOT"]?.trimmingCharacters(in: .whitespacesAndNewlines), !root.isEmpty {
            self.fountainRepoRoot = URL(fileURLWithPath: root, isDirectory: true)
        } else {
            self.fountainRepoRoot = nil
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

    private static func resolveBootstrapURL(from env: [String: String]) -> URL? {
        if let raw = env["BOOTSTRAP_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "http://127.0.0.1:8002")
    }

    private static func resolveSeedingConfiguration(from env: [String: String]) -> SeedingConfiguration? {
        let baseDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let sources = resolveSeedSources(from: env, relativeTo: baseDirectory)
        guard !sources.isEmpty else {
            return nil
        }

        let browserBase = env["ENGRAVER_SEED_BROWSER_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let browserURL = browserBase.flatMap(URL.init(string:)) ?? URL(string: "http://127.0.0.1:8007")!

        var browserAPIKey = env["ENGRAVER_SEED_BROWSER_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if (browserAPIKey?.isEmpty ?? true),
           let secretRef = env["ENGRAVER_SEED_BROWSER_API_KEY_SECRET"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !secretRef.isEmpty,
           let separator = secretRef.firstIndex(of: ":") {
            let service = String(secretRef[..<separator])
            let account = String(secretRef[secretRef.index(after: separator)...])
            browserAPIKey = SecretStoreHelper.read(service: service, account: account)
        }
        if browserAPIKey?.isEmpty == true {
            browserAPIKey = nil
        }

        let labelsRaw = env["ENGRAVER_SEED_BROWSER_LABELS"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let labels = labelsRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let resolvedLabels = labels

        let modeRaw = env["ENGRAVER_SEED_BROWSER_MODE"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let browserMode = SeedingConfiguration.Browser.Mode(rawValue: modeRaw) ?? .standard

        let pagesCollection = env["ENGRAVER_SEED_PAGES_COLLECTION"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let segmentsCollection = env["ENGRAVER_SEED_SEGMENTS_COLLECTION"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let entitiesCollection = env["ENGRAVER_SEED_ENTITIES_COLLECTION"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tablesCollection = env["ENGRAVER_SEED_TABLES_COLLECTION"]?.trimmingCharacters(in: .whitespacesAndNewlines)

        let storeURLRaw = env["ENGRAVER_SEED_STORE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storeURL = URL(string: storeURLRaw)
        var storeAPIKey = env["ENGRAVER_SEED_STORE_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if (storeAPIKey?.isEmpty ?? true),
           let secretRef = env["ENGRAVER_SEED_STORE_API_KEY_SECRET"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !secretRef.isEmpty,
           let separator = secretRef.firstIndex(of: ":") {
            let service = String(secretRef[..<separator])
            let account = String(secretRef[secretRef.index(after: separator)...])
            storeAPIKey = SecretStoreHelper.read(service: service, account: account)
        }
        if storeAPIKey?.isEmpty == true {
            storeAPIKey = nil
        }
        let timeoutRaw = env["ENGRAVER_SEED_STORE_TIMEOUT_MS"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let timeout = Int(timeoutRaw)
        let storeOverride: SeedingConfiguration.Browser.StoreOverride?
        if let storeURL {
            storeOverride = .init(url: storeURL, apiKey: storeAPIKey, timeoutMs: timeout)
        } else {
            storeOverride = nil
        }

        let browser = SeedingConfiguration.Browser(
            baseURL: browserURL,
            apiKey: browserAPIKey,
            mode: browserMode,
            defaultLabels: resolvedLabels,
            pagesCollection: pagesCollection?.isEmpty == true ? nil : pagesCollection,
            segmentsCollection: segmentsCollection?.isEmpty == true ? nil : segmentsCollection,
            entitiesCollection: entitiesCollection?.isEmpty == true ? nil : entitiesCollection,
            tablesCollection: tablesCollection?.isEmpty == true ? nil : tablesCollection,
            storeOverride: storeOverride
        )

        return SeedingConfiguration(sources: sources, browser: browser)
    }

    private static func resolvePath(_ rawPath: String, relativeTo base: URL, isDirectory: Bool) -> URL {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return base
        }
        if trimmed.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let suffix = trimmed.dropFirst()
            return home.appendingPathComponent(String(suffix), isDirectory: isDirectory).standardizedFileURL
        }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed, isDirectory: isDirectory).standardizedFileURL
        }
        return base.appendingPathComponent(trimmed, isDirectory: isDirectory).standardizedFileURL
    }

    private static func resolveSeedSources(from env: [String: String], relativeTo base: URL) -> [SeedingConfiguration.Source] {
        var rawEntries: [String] = []
        if let explicit = env["ENGRAVER_SEED_SOURCES"]?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            rawEntries = explicit
                .split(whereSeparator: { $0 == ";" || $0 == "\n" })
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        if rawEntries.isEmpty {
            // Backwards compatibility with legacy repo/script variables.
            let repoRaw = env["ENGRAVER_SEED_REPO"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let repoDefault = repoRaw?.isEmpty == false ? repoRaw! : "Workspace/the-four-stars"
            let repoURL = resolvePath(repoDefault, relativeTo: base, isDirectory: true)
            let scriptRaw = env["ENGRAVER_SEED_SCRIPT"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let scriptPath = scriptRaw?.isEmpty == false ? scriptRaw! : "the four stars"
            let legacyPath = repoURL.appendingPathComponent(scriptPath)
            rawEntries = [legacyPath.path]
        }

        if rawEntries.isEmpty {
            let fallback = "Workspace/the-four-stars/the four stars"
            rawEntries = [fallback]
        }

        let defaultLabels = env["ENGRAVER_SEED_BROWSER_LABELS"]?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        var sources: [SeedingConfiguration.Source] = []
        for raw in rawEntries {
            guard let source = decodeSourceEntry(raw, defaultLabels: defaultLabels, base: base) else { continue }
            sources.append(source)
        }
        return sources
    }

    private static func decodeSourceEntry(_ raw: String, defaultLabels: [String], base: URL) -> SeedingConfiguration.Source? {
        let parts = raw.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var location: String?
        var name: String?
        var corpusId: String?
        var labels: [String] = []

        if parts.isEmpty {
            location = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            for part in parts {
                if part.hasPrefix("name=") {
                    name = String(part.dropFirst("name=".count))
                } else if part.hasPrefix("corpus=") {
                    corpusId = String(part.dropFirst("corpus=".count))
                } else if part.hasPrefix("labels=") {
                    let value = String(part.dropFirst("labels=".count))
                    labels = value
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                } else if part.hasPrefix("url=") {
                    location = String(part.dropFirst("url=".count))
                } else if part.hasPrefix("path=") {
                    location = String(part.dropFirst("path=".count))
                } else if location == nil {
                    location = part
                }
            }
        }

        guard let locationString = location, !locationString.isEmpty else {
            return nil
        }

        guard let url = resolveSourceURL(locationString, base: base) else {
            return nil
        }

        let displayName = name ?? deriveDisplayName(from: url)
        let slug = corpusId?.isEmpty == false ? corpusId! : slugify(displayName)
        let resolvedLabels = labels.isEmpty ? (defaultLabels.isEmpty ? [slug] : defaultLabels) : labels
        return SeedingConfiguration.Source(name: displayName, url: url, corpusId: slug, labels: resolvedLabels)
    }

    private static func resolveSourceURL(_ raw: String, base: URL) -> URL? {
        if let asURL = URL(string: raw), asURL.scheme != nil {
            return asURL
        }
        let candidate = resolvePath(raw, relativeTo: base, isDirectory: false)
        if FileManager.default.fileExists(atPath: candidate.path) {
            if candidate.isFileURL {
                return candidate
            }
        }
        // Treat as file even if it does not yet exist (allow future authoring).
        return candidate
    }

    private static func deriveDisplayName(from url: URL) -> String {
        if url.isFileURL {
            return url.deletingPathExtension().lastPathComponent
        }
        return url.absoluteString
    }

    private static func slugify(_ value: String) -> String {
        let lowered = value.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        var cleaned = lowered.replacingOccurrences(of: " ", with: "-")
        cleaned = cleaned.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }.map(String.init).joined()
        cleaned = cleaned.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "semantic-corpus" : trimmed
    }
}
