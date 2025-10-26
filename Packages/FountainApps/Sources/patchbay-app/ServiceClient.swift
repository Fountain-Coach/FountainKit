import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

// Lightweight protocol to enable dependency injection for tests
@MainActor
protocol PatchBayAPI {
    func listInstruments() async throws -> [Components.Schemas.Instrument]
    func suggestLinks(nodeIds: [String]) async throws -> [Components.Schemas.SuggestedLink]
}

@MainActor
final class PatchBayClient: PatchBayAPI {
    private let client: Client
    private let transport: URLSessionTransport

    init(baseURL: URL = URL(string: "http://127.0.0.1:7090")!) {
        self.transport = URLSessionTransport()
        self.client = Client(serverURL: baseURL, transport: transport)
    }

    func listInstruments() async throws -> [Components.Schemas.Instrument] {
        switch try await client.listInstruments(.init()) {
        case .ok(let ok): return try ok.body.json
        default: return []
        }
    }

    func suggestLinks(nodeIds: [String] = []) async throws -> [Components.Schemas.SuggestedLink] {
        let body = Operations.suggestLinks.Input.Body.jsonPayload(nodeIds: nodeIds, includeUMP: true)
        switch try await client.suggestLinks(.init(body: .json(body))) {
        case .ok(let ok): return try ok.body.json
        default: return []
        }
    }

    // Admin
    func getVendorIdentity() async throws -> Components.Schemas.VendorIdentity? {
        switch try await client.getVendorIdentity(.init()) {
        case .ok(let ok): return try ok.body.json
        default: return nil
        }
    }
    func putVendorIdentity(_ v: Components.Schemas.VendorIdentity) async throws {
        _ = try await client.putVendorIdentity(.init(body: .json(v)))
    }

    // Corpus
    func createCorpusSnapshot(includeSchemas: Bool = true, includeMappings: Bool = true) async throws -> Components.Schemas.CorpusSnapshot? {
        let payload = Operations.createCorpusSnapshot.Input.Body.jsonPayload(includeSchemas: includeSchemas, includeMappings: includeMappings)
        switch try await client.createCorpusSnapshot(.init(body: .json(payload))) {
        case .ok(let ok): return try ok.body.json
        default: return nil
        }
    }

    // Links
    func createLink(_ link: Components.Schemas.CreateLink) async throws -> Components.Schemas.Link? {
        switch try await client.createLink(.init(body: .json(link))) {
        case .created(let c): return try c.body.json
        default: return nil
        }
    }
    func listLinks() async throws -> [Components.Schemas.Link] {
        switch try await client.listLinks(.init()) {
        case .ok(let ok): return try ok.body.json
        default: return []
        }
    }
    func deleteLink(id: String) async throws {
        _ = try await client.deleteLink(.init(path: .init(id: id)))
    }

    // Store
    func listStoredGraphs() async throws -> [Components.Schemas.StoredGraph] {
        switch try await client.listStoredGraphs(.init()) {
        case .ok(let ok): return try ok.body.json
        default: return []
        }
    }
    func getStoredGraph(id: String) async throws -> Components.Schemas.StoredGraph? {
        switch try await client.getStoredGraph(.init(path: .init(id: id))) {
        case .ok(let ok): return try ok.body.json
        default: return nil
        }
    }
    func putStoredGraph(id: String, doc: Components.Schemas.GraphDoc) async throws {
        let sg = Components.Schemas.StoredGraph(id: id, doc: doc, createdAt: nil, updatedAt: nil, etag: nil)
        _ = try await client.putStoredGraph(.init(path: .init(id: id), body: .json(sg)))
    }
}
