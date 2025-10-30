import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

// Lightweight protocol to enable dependency injection for tests
@MainActor
protocol PatchBayAPI {
    func listInstruments() async throws -> [Components.Schemas.Instrument]
    func suggestLinks(nodeIds: [String]) async throws -> [Components.Schemas.SuggestedLink]
    func createInstrument(id: String, kind: Components.Schemas.InstrumentKind, title: String?, x: Int, y: Int, w: Int, h: Int) async throws -> Components.Schemas.Instrument?
}

@MainActor
final class PatchBayClient: PatchBayAPI {
    private let client: Client
    private let transport: URLSessionTransport
    let baseURL: URL

    init(baseURL: URL = URL(string: "http://127.0.0.1:7090")!) {
        // Custom URLSession with sane timeouts and no connectivity waits to avoid long hangs
        let cfg = URLSessionConfiguration.default
        // Respect env overrides if provided
        let env = ProcessInfo.processInfo.environment
        let reqTimeout = TimeInterval(Double(env["PATCHBAY_NET_TIMEOUT"] ?? "8") ?? 8)
        let resTimeout = TimeInterval(Double(env["PATCHBAY_NET_RESOURCE_TIMEOUT"] ?? "20") ?? 20)
        cfg.timeoutIntervalForRequest = reqTimeout
        cfg.timeoutIntervalForResource = resTimeout
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: cfg)
        self.transport = URLSessionTransport(configuration: .init(session: session))
        self.client = Client(serverURL: baseURL, transport: transport)
        self.baseURL = baseURL
    }

    func listInstruments() async throws -> [Components.Schemas.Instrument] {
        NetDebug.log("GET /instruments — start")
        let t0 = Date()
        defer { NetDebug.log(String(format: "GET /instruments — end (%.2fs)", Date().timeIntervalSince(t0))) }
        switch try await client.listInstruments(.init()) {
        case .ok(let ok): return try ok.body.json
        default: return []
        }
    }

    func suggestLinks(nodeIds: [String] = []) async throws -> [Components.Schemas.SuggestedLink] {
        let body = Operations.suggestLinks.Input.Body.jsonPayload(nodeIds: nodeIds, includeUMP: true)
        NetDebug.log("POST /graph/suggest — start (ids=\(nodeIds.count))")
        let t0 = Date()
        defer { NetDebug.log(String(format: "POST /graph/suggest — end (%.2fs)", Date().timeIntervalSince(t0))) }
        switch try await client.suggestLinks(.init(body: .json(body))) {
        case .ok(let ok): return try ok.body.json
        default: return []
        }
    }

    // Admin
    func getVendorIdentity() async throws -> Components.Schemas.VendorIdentity? {
        NetDebug.log("GET /admin/vendor-identity — start")
        let t0 = Date()
        defer { NetDebug.log(String(format: "GET /admin/vendor-identity — end (%.2fs)", Date().timeIntervalSince(t0))) }
        switch try await client.getVendorIdentity(.init()) {
        case .ok(let ok): return try ok.body.json
        default: return nil
        }
    }
    func putVendorIdentity(_ v: Components.Schemas.VendorIdentity) async throws {
        NetDebug.log("PUT /admin/vendor-identity — start")
        let t0 = Date()
        defer { NetDebug.log(String(format: "PUT /admin/vendor-identity — end (%.2fs)", Date().timeIntervalSince(t0))) }
        _ = try await client.putVendorIdentity(.init(body: .json(v)))
    }

    // Corpus
    func createCorpusSnapshot(includeSchemas: Bool = true, includeMappings: Bool = true) async throws -> Components.Schemas.CorpusSnapshot? {
        let payload = Operations.createCorpusSnapshot.Input.Body.jsonPayload(includeSchemas: includeSchemas, includeMappings: includeMappings)
        NetDebug.log("POST /corpus/snapshot — start")
        let t0 = Date()
        defer { NetDebug.log(String(format: "POST /corpus/snapshot — end (%.2fs)", Date().timeIntervalSince(t0))) }
        switch try await client.createCorpusSnapshot(.init(body: .json(payload))) {
        case .ok(let ok): return try ok.body.json
        default: return nil
        }
    }

    // Links
    func createLink(_ link: Components.Schemas.CreateLink) async throws -> Components.Schemas.Link? {
        NetDebug.log("POST /links — start")
        let t0 = Date()
        defer { NetDebug.log(String(format: "POST /links — end (%.2fs)", Date().timeIntervalSince(t0))) }
        switch try await client.createLink(.init(body: .json(link))) {
        case .created(let c): return try c.body.json
        default: return nil
        }
    }
    func listLinks() async throws -> [Components.Schemas.Link] {
        NetDebug.log("GET /links — start")
        let t0 = Date()
        defer { NetDebug.log(String(format: "GET /links — end (%.2fs)", Date().timeIntervalSince(t0))) }
        switch try await client.listLinks(.init()) {
        case .ok(let ok): return try ok.body.json
        default: return []
        }
    }
    func deleteLink(id: String) async throws {
        NetDebug.log("DELETE /links/\(id) — start")
        let t0 = Date()
        defer { NetDebug.log(String(format: "DELETE /links/%@ — end (%.2fs)", id, Date().timeIntervalSince(t0))) }
        _ = try await client.deleteLink(.init(path: .init(id: id)))
    }

    // Instruments
    func createInstrument(id: String, kind: Components.Schemas.InstrumentKind, title: String?, x: Int, y: Int, w: Int, h: Int) async throws -> Components.Schemas.Instrument? {
        let payload = Components.Schemas.CreateInstrument(id: id, kind: kind, title: title, x: x, y: y, w: w, h: h, identity: nil)
        switch try await client.createInstrument(.init(body: .json(payload))) {
        case .created(let c): return try c.body.json
        default: return nil
        }
    }

    // Store
    func listStoredGraphs() async throws -> [Components.Schemas.StoredGraph] {
        NetDebug.log("GET /store/graphs — start")
        let t0 = Date()
        defer { NetDebug.log(String(format: "GET /store/graphs — end (%.2fs)", Date().timeIntervalSince(t0))) }
        switch try await client.listStoredGraphs(.init()) {
        case .ok(let ok): return try ok.body.json
        default: return []
        }
    }
    func getStoredGraph(id: String) async throws -> Components.Schemas.StoredGraph? {
        NetDebug.log("GET /store/graphs/\(id) — start")
        let t0 = Date()
        defer { NetDebug.log(String(format: "GET /store/graphs/%@ — end (%.2fs)", id, Date().timeIntervalSince(t0))) }
        switch try await client.getStoredGraph(.init(path: .init(id: id))) {
        case .ok(let ok): return try ok.body.json
        default: return nil
        }
    }
    func putStoredGraph(id: String, doc: Components.Schemas.GraphDoc) async throws {
        let sg = Components.Schemas.StoredGraph(id: id, doc: doc, createdAt: nil, updatedAt: nil, etag: nil)
        NetDebug.log("PUT /store/graphs/\(id) — start")
        let t0 = Date()
        defer { NetDebug.log(String(format: "PUT /store/graphs/%@ — end (%.2fs)", id, Date().timeIntervalSince(t0))) }
        _ = try await client.putStoredGraph(.init(path: .init(id: id), body: .json(sg)))
    }
}

// Minimal network debug logger that writes to .fountain/logs/patchbay-app.log when PATCHBAY_DEBUG=1
enum NetDebug {
    private static let enabled: Bool = {
        ProcessInfo.processInfo.environment["PATCHBAY_DEBUG"] == "1"
    }()
    static func log(_ message: String) {
        guard enabled else { return }
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let dir = cwd.appendingPathComponent(".fountain/logs", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("patchbay-app.log")
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: path.path) {
                if let h = try? FileHandle(forWritingTo: path) { defer { try? h.close() }; try? h.seekToEnd(); try? h.write(contentsOf: data) }
            } else {
                try? data.write(to: path)
            }
        }
    }
}
