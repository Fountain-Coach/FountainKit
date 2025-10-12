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
    private let warmupRetryInterval: TimeInterval

    /// Create a plugin pointing at the given curator service URL.
    /// - Parameter curatorURL: Base URL of the curator service.
    public init(curatorURL: URL = URL(string: "http://curator.fountain.coach/api/v1")!, warmupRetryInterval: TimeInterval = 30) {
        self.warmupRetryInterval = warmupRetryInterval
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
    public init(fetcher: @escaping @Sendable () async throws -> TruthTable,
                warmupRetryInterval: TimeInterval = 30) {
        self.warmupRetryInterval = warmupRetryInterval
        self.fetchTable = fetcher
    }

    /// Loads the curator truth table on first request.
    public func prepare(_ request: HTTPRequest) async throws -> HTTPRequest {
        await cache.ensureLoaded(fetcher: fetchTable,
                                 retryInterval: warmupRetryInterval,
                                 onFailure: { error in
            FileHandle.standardError.write(Data("[curator] warning: failed to warm truth table (\(error))\n".utf8))
        })
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
        guard let op = request.headers["X-Operation-ID"], !op.isEmpty else {
            return response
        }

        await cache.ensureLoaded(fetcher: fetchTable,
                                 retryInterval: warmupRetryInterval,
                                 onFailure: { error in
            FileHandle.standardError.write(Data("[curator] warning: failed to refresh truth table (\(error))\n".utf8))
        })

        if let truth = await cache.lookup(op) {
            var resp = response
            resp.headers["X-Curator-Evidence"] = truth.reason
            return resp
        }

        let state = await cache.status()
        if state.hasTable {
            return HTTPResponse(status: 403,
                                headers: ["Content-Type": "application/json"],
                                body: Data("{\"error\":\"operation lacks evidence\"}".utf8))
        }

        var resp = response
        let warning: String
        if let err = state.lastError {
            warning = "curator unavailable: \(err.localizedDescription)"
        } else {
            warning = "curator warming"
        }
        resp.headers["X-Curator-Warning"] = warning
        return resp
    }
}

/// Actor-backed cache for curator truth table.
actor TruthTableCache {
    private var table: CuratorGatewayPlugin.TruthTable = [:]
    private var loadTask: Task<Void, Never>?
    private var lastAttempt: Date?
    private var lastErrorStorage: NSError?

    func ensureLoaded(fetcher: @Sendable @escaping () async throws -> CuratorGatewayPlugin.TruthTable,
                      retryInterval: TimeInterval,
                      onFailure: @escaping @Sendable (Error) -> Void) async {
        if !table.isEmpty { return }
        if let task = loadTask {
            if task.isCancelled { loadTask = nil }
            else { return }
        }
        let now = Date()
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < retryInterval {
            return
        }
        lastAttempt = now
        loadTask = Task {
            do {
                let fetched = try await fetcher()
                await self.store(table: fetched, error: nil)
            } catch {
                await self.store(table: nil, error: error as NSError)
                onFailure(error)
            }
        }
    }

    func lookup(_ op: String) -> CuratorGatewayPlugin.Truth? {
        table[op]
    }

    func status() -> (hasTable: Bool, lastError: Error?, isLoading: Bool) {
        (hasTable: !table.isEmpty, lastError: lastErrorStorage, isLoading: loadTask != nil)
    }

    private func store(table: CuratorGatewayPlugin.TruthTable?, error: NSError?) {
        if let table { self.table = table }
        self.lastErrorStorage = error
        self.loadTask = nil
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
