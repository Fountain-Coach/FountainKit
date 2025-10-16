import Foundation

public struct SemanticBrowserSeeder {
    public struct Metrics: Sendable {
        public let pagesUpserted: Int
        public let segmentsUpserted: Int
        public let entitiesUpserted: Int
        public let tablesUpserted: Int

        public init(pagesUpserted: Int, segmentsUpserted: Int, entitiesUpserted: Int, tablesUpserted: Int) {
            self.pagesUpserted = pagesUpserted
            self.segmentsUpserted = segmentsUpserted
            self.entitiesUpserted = entitiesUpserted
            self.tablesUpserted = tablesUpserted
        }
    }

    public enum SeedingError: Error, CustomStringConvertible, Sendable {
        case invalidResponse
        case httpStatus(Int, String?)
        case decodingFailure(String)

        public var description: String {
            switch self {
            case .invalidResponse:
                return "Semantic Browser response missing HTTP metadata."
            case .httpStatus(let code, let body):
                if let body, !body.isEmpty {
                    return "Semantic Browser returned status \(code): \(body)"
                }
                return "Semantic Browser returned status \(code)."
            case .decodingFailure(let reason):
                return "Failed to decode Semantic Browser response: \(reason)"
            }
        }
    }

    public typealias RequestPerformer = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let performRequest: RequestPerformer

    public init(requestPerformer: RequestPerformer? = nil) {
        if let requestPerformer {
            self.performRequest = requestPerformer
        } else {
            self.performRequest = { request in
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw SeedingError.invalidResponse
                }
                return (data, http)
            }
        }
    }

    public func run(
        source: EngraverStudioConfiguration.SeedingConfiguration.Source,
        browser: EngraverStudioConfiguration.SeedingConfiguration.Browser,
        emitDiagnostic: @Sendable (String) -> Void
    ) async throws -> Metrics {
        let combinedLabels = Array(Set(browser.defaultLabels + source.labels + [source.corpusId]))

        let endpoint = browser.baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("browse")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = browser.apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        var indexOptions: [String: Any] = ["enabled": true]
        if let pages = browser.pagesCollection, !pages.isEmpty {
            indexOptions["pagesCollection"] = pages
        }
        if let segments = browser.segmentsCollection, !segments.isEmpty {
            indexOptions["segmentsCollection"] = segments
        }
        if let entities = browser.entitiesCollection, !entities.isEmpty {
            indexOptions["entitiesCollection"] = entities
        }
        if let tables = browser.tablesCollection, !tables.isEmpty {
            indexOptions["tablesCollection"] = tables
        }
        if let store = browser.storeOverride {
            var storeOptions: [String: Any] = ["url": store.url.absoluteString]
            if let key = store.apiKey, !key.isEmpty {
                storeOptions["apiKey"] = key
            }
            if let timeout = store.timeoutMs {
                storeOptions["timeoutMs"] = timeout
            }
            indexOptions["store"] = storeOptions
        }

        let waitPolicy: [String: Any] = [
            "strategy": "domContentLoaded",
            "maxWaitMs": 20000
        ]

        let body: [String: Any] = [
            "url": source.url.absoluteString,
            "wait": waitPolicy,
            "mode": browser.mode.rawValue,
            "index": indexOptions,
            "storeArtifacts": true,
            "labels": combinedLabels
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            throw SeedingError.decodingFailure("Unable to encode request body: \(error)")
        }

        emitDiagnostic("Indexing \(source.name) via Semantic Browser (\(source.url.absoluteString))")
        let (data, response) = try await performRequest(request)
        guard response.statusCode == 200 else {
            let bodyText = String(data: data, encoding: .utf8)
            throw SeedingError.httpStatus(response.statusCode, bodyText)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let browseResponse: BrowseResponse
        do {
            browseResponse = try decoder.decode(BrowseResponse.self, from: data)
        } catch {
            throw SeedingError.decodingFailure(error.localizedDescription)
        }

        let metrics = browseResponse.index ?? BrowseResponse.IndexSummary()
        return Metrics(
            pagesUpserted: metrics.pagesUpserted ?? 0,
            segmentsUpserted: metrics.segmentsUpserted ?? 0,
            entitiesUpserted: metrics.entitiesUpserted ?? 0,
            tablesUpserted: metrics.tablesUpserted ?? 0
        )
    }
}

private extension SemanticBrowserSeeder {
    struct BrowseResponse: Decodable {
        struct IndexSummary: Decodable {
            let pagesUpserted: Int?
            let segmentsUpserted: Int?
            let entitiesUpserted: Int?
            let tablesUpserted: Int?

            init(
                pagesUpserted: Int? = nil,
                segmentsUpserted: Int? = nil,
                entitiesUpserted: Int? = nil,
                tablesUpserted: Int? = nil
            ) {
                self.pagesUpserted = pagesUpserted
                self.segmentsUpserted = segmentsUpserted
                self.entitiesUpserted = entitiesUpserted
                self.tablesUpserted = tablesUpserted
            }
        }

        let index: IndexSummary?
    }
}
