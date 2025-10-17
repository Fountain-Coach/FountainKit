import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import ApiClientsCore
import SemanticBrowserAPI

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

    // Optional test hook for injecting a fake HTTP performer (backwards-compat for existing tests)
    private let requestPerformer: (@Sendable (URLRequest) async throws -> (Data, HTTPURLResponse))?

    public init() {
        self.requestPerformer = nil
    }

    public init(requestPerformer: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)) {
        self.requestPerformer = requestPerformer
    }

    public func run(
        source: EngraverStudioConfiguration.SeedingConfiguration.Source,
        browser: EngraverStudioConfiguration.SeedingConfiguration.Browser,
        emitDiagnostic: @Sendable (String) -> Void
    ) async throws -> Metrics {
        // Compose default headers (API key if present)
        var defaultHeaders: [String: String] = [:]
        if let apiKey = browser.apiKey, !apiKey.isEmpty {
            defaultHeaders["X-API-Key"] = apiKey
        }

        // Build request payload from configuration
        let combinedLabels = Array(Set(browser.defaultLabels + source.labels + [source.corpusId]))

        let wait = Components.Schemas.WaitPolicy(
            strategy: .domContentLoaded,
            networkIdleMs: nil,
            selector: nil,
            maxWaitMs: 20000
        )

        let storeOverride: Components.Schemas.IndexOptions.storePayload? = {
            guard let o = browser.storeOverride else { return nil }
            return .init(url: o.url.absoluteString, apiKey: o.apiKey, timeoutMs: o.timeoutMs)
        }()

        let indexOptions = Components.Schemas.IndexOptions(
            enabled: true,
            pagesCollection: browser.pagesCollection,
            segmentsCollection: browser.segmentsCollection,
            entitiesCollection: browser.entitiesCollection,
            tablesCollection: browser.tablesCollection,
            store: storeOverride
        )

        let request = Components.Schemas.BrowseRequest(
            url: source.url.absoluteString,
            wait: wait,
            mode: Components.Schemas.DissectionMode(rawValue: browser.mode.rawValue) ?? .standard,
            index: indexOptions,
            storeArtifacts: true,
            labels: combinedLabels
        )

        emitDiagnostic("Indexing \(source.name) via Semantic Browser (\(source.url.absoluteString))")

        // If a request performer is injected (tests), bypass the generated client and decode the stubbed response.
        if let requestPerformer {
            var urlRequest = URLRequest(url: browser.baseURL.appendingPathComponent("v1").appendingPathComponent("browse"))
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            for (k, v) in defaultHeaders { urlRequest.setValue(v, forHTTPHeaderField: k) }
            urlRequest.httpBody = try JSONEncoder().encode(request)

            let (data, response) = try await requestPerformer(urlRequest)
            guard response.statusCode == 200 else {
                throw SeedingError.httpStatus(response.statusCode, String(data: data, encoding: .utf8))
            }
            let decoded = try JSONDecoder().decode(Components.Schemas.BrowseResponse.self, from: data)
            let metrics = decoded.index
            return Metrics(
                pagesUpserted: metrics?.pagesUpserted ?? 0,
                segmentsUpserted: metrics?.segmentsUpserted ?? 0,
                entitiesUpserted: metrics?.entitiesUpserted ?? 0,
                tablesUpserted: metrics?.tablesUpserted ?? 0
            )
        }

        let transport = URLSessionTransport()
        let middlewares = APIClientHelpers.defaultMiddlewares(defaultHeaders: defaultHeaders)
        let client = SemanticBrowserAPI.Client(serverURL: browser.baseURL, transport: transport, middlewares: middlewares)
        let output = try await client.browseAndDissect(.init(body: .json(request)))
        switch output {
        case .ok(let ok):
            let response = try ok.body.json
            let metrics = response.index
            return Metrics(
                pagesUpserted: metrics?.pagesUpserted ?? 0,
                segmentsUpserted: metrics?.segmentsUpserted ?? 0,
                entitiesUpserted: metrics?.entitiesUpserted ?? 0,
                tablesUpserted: metrics?.tablesUpserted ?? 0
            )
        case .badRequest:
            throw SeedingError.httpStatus(400, "Bad Request")
        case .tooManyRequests:
            throw SeedingError.httpStatus(429, "Too Many Requests")
        case .internalServerError:
            throw SeedingError.httpStatus(500, "Server Error")
        case .undocumented(let status, _):
            throw SeedingError.httpStatus(status, nil)
        }
    }
}
