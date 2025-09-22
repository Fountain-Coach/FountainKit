import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FountainRuntime
import OpenAPICurator

extension OpenAPICurator.Truth: @retroactive @unchecked Sendable {}

/// Gateway plugin that consults the curator service for evidence-based operation gating.
public struct CuratorGatewayPlugin: Sendable {
    public typealias Truth = OpenAPICurator.Truth
    public typealias TruthTable = [String: Truth]

    private let fetchTable: @Sendable () async throws -> TruthTable
    private let cache = TruthTableCache()

    /// Create a plugin pointing at the given curator service URL.
    /// - Parameter curatorURL: Base URL of the curator service.
    public init(curatorURL: URL = URL(string: "http://curator.fountain.coach/api/v1")!) {
        self.fetchTable = {
            var req = URLRequest(url: curatorURL.appendingPathComponent("truth-table"))
            req.httpMethod = "POST"
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data("{}".utf8)
            let (data, _) = try await URLSession.shared.data(for: req)
            let table = try JSONDecoder().decode(TruthTable.self, from: data)
            return table
        }
    }

    /// Create a plugin with a custom fetcher, used mainly for tests.
    public init(fetcher: @escaping @Sendable () async throws -> TruthTable) {
        self.fetchTable = fetcher
    }

    /// Loads the curator truth table on first request.
    public func prepare(_ request: HTTPRequest) async throws -> HTTPRequest {
        try await cache.loadIfNeeded(fetcher: fetchTable)
        return request
    }

    /// Returns whether an operation has curator evidence.
    public func allowed(operation: String) async -> Bool {
        if let truth = await cache.lookup(operation) {
            return !truth.reason.isEmpty
        }
        return false
    }

    /// Annotates responses with curator evidence or rejects when missing.
    public func respond(_ response: HTTPResponse, for request: HTTPRequest) async throws -> HTTPResponse {
        guard let op = request.headers["X-Operation-ID"], !op.isEmpty else { return response }
        if let truth = await cache.lookup(op) {
            var resp = response
            resp.headers["X-Curator-Evidence"] = truth.reason
            return resp
        }
        return HTTPResponse(status: 403,
                            headers: ["Content-Type": "application/json"],
                            body: Data("{\"error\":\"operation lacks evidence\"}".utf8))
    }
}

/// Actor-backed cache for curator truth table.
actor TruthTableCache {
    private var table: CuratorGatewayPlugin.TruthTable = [:]

    func loadIfNeeded(fetcher: @Sendable () async throws -> CuratorGatewayPlugin.TruthTable) async throws {
        if table.isEmpty {
            table = try await fetcher()
        }
    }

    func lookup(_ op: String) -> CuratorGatewayPlugin.Truth? {
        table[op]
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
