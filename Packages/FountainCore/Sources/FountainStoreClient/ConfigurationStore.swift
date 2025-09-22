import Foundation

/// Convenience wrapper for storing configuration files inside FountainStore.
public actor ConfigurationStore {
    private let client: FountainStoreClient
    private let corpusId: String
    private let collection = "config"

    public init(client: FountainStoreClient, corpusId: String) {
        self.client = client
        self.corpusId = corpusId
    }

    /// Reads a configuration document by name.
    public func get(_ name: String) async throws -> Data? {
        try await client.getDoc(corpusId: corpusId, collection: collection, id: name)
    }

    /// Writes a configuration document.
    public func put(_ name: String, data: Data) async throws {
        try await client.putDoc(corpusId: corpusId, collection: collection, id: name, body: data)
    }

    /// Synchronously fetches a configuration document.
    public nonisolated func getSync(_ name: String) -> Data? {
        let sema = DispatchSemaphore(value: 0)
        var result: Data?
        Task {
            result = try? await get(name)
            sema.signal()
        }
        sema.wait()
        return result
    }
}

public extension ConfigurationStore {
    /// Creates a store instance from environment variables if possible.
    /// Returns `nil` when required variables are missing.
    static func fromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment,
                                client: FountainStoreClient? = nil) -> ConfigurationStore? {
        guard env["FOUNTAINSTORE_URL"] != nil,
              env["FOUNTAINSTORE_API_KEY"] != nil,
              let corpus = env["DEFAULT_CORPUS_ID"] ?? env["CORPUS_ID"] else {
            return nil
        }
        let svc = client ?? FountainStoreClient(client: EmbeddedFountainStoreClient())
        return ConfigurationStore(client: svc, corpusId: corpus)
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
