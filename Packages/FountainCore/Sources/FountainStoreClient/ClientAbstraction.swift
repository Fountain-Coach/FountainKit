import Foundation

public protocol FountainStoreClientProtocol: Sendable {
    // MARK: - Corpus
    func createCorpus(id: String, metadata: [String: String]) async throws
    func getCorpus(id: String) async throws -> Corpus?
    func deleteCorpus(id: String) async throws
    func listCorpora(limit: Int, offset: Int) async throws -> (total: Int, corpora: [String])

    // MARK: - Documents
    func putDoc(corpusId: String, collection: String, id: String, body: Data) async throws
    func getDoc(corpusId: String, collection: String, id: String) async throws -> Data?
    func deleteDoc(corpusId: String, collection: String, id: String) async throws
    func query(corpusId: String, collection: String, query: Query) async throws -> QueryResponse

    // MARK: - Capabilities
    func capabilities() async throws -> Capabilities

    // MARK: - Admin
    func snapshot(corpusId: String) async throws
    func restore(corpusId: String) async throws
    func backup(corpusId: String) async throws
    func compaction(corpusId: String) async throws
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.

