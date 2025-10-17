import Foundation

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

        public enum Mode: String, Sendable { case quick, standard, deep }

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

