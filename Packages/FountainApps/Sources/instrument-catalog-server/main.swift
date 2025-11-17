import Foundation
import FountainRuntime
import FountainStoreClient
import LauncherSignature

struct CatalogItem: Codable, Sendable {
    var id: String
    var title: String
    var summary: String?
    var group: String?
    var agentIds: [String]
    var iconURL: String?
    var version: String?
    var enabled: Bool = true
    var pricing: Pricing?
    struct Pricing: Codable, Sendable { var platform: String; var productId: String; var currency: String?; var tier: String? }
}

@main
enum InstrumentCatalogServer {
    static func main() async {
        verifyLauncherSignature()
        let env = ProcessInfo.processInfo.environment
        let corpus = env["CATALOG_CORPUS_ID"] ?? env["CORPUS_ID"] ?? "instruments"
        let store: FountainStoreClient = {
            if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
                let url = URL(fileURLWithPath: dir, isDirectory: true)
                if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
            }
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) { return FountainStoreClient(client: disk) }
            return FountainStoreClient(client: EmbeddedFountainStoreClient())
        }()

        let kernel = HTTPKernel { req in
            // Health
            if req.method == "GET" && req.path == "/metrics" { return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: Data("instrument_catalog_up 1\n".utf8)) }
            // List instruments (via index doc)
            if req.method == "GET" && req.path == "/catalog/instruments" {
                var items: [[String: Any]] = []
                if let idxData = try? await store.getDoc(corpusId: corpus, collection: "instrument-catalog", id: "instrument-catalog:index"),
                   let idxObj = try? JSONSerialization.jsonObject(with: idxData) as? [String: Any],
                   let ids = idxObj["ids"] as? [String] {
                    for id in ids {
                        let key = "instrument:\(id)"
                        if let d = try? await store.getDoc(corpusId: corpus, collection: "instrument-catalog", id: key),
                           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { items.append(o) }
                    }
                }
                let data = try? JSONSerialization.data(withJSONObject: ["items": items])
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data ?? Data())
            }
            // Get instrument by id
            if req.method == "GET", req.path.hasPrefix("/catalog/instrument/") {
                let id = String(req.path.dropFirst("/catalog/instrument/".count))
                let key = "instrument:\(id)"
                if let d = try? await store.getDoc(corpusId: corpus, collection: "instrument-catalog", id: key) {
                    return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: d)
                }
                return HTTPResponse(status: 404, headers: ["Content-Type": "application/json"], body: Data("{\"error\":\"not_found\"}".utf8))
            }
            // Register/update instrument
            if req.method == "POST" && req.path == "/catalog/instrument" {
                guard let obj = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any], let id = (obj["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
                    return HTTPResponse(status: 400, headers: ["Content-Type": "application/json"], body: Data("{\"error\":\"invalid_request\"}".utf8))
                }
                let key = "instrument:\(id)"
                // Normalize minimal fields, pass-through others
                var doc = obj
                if doc["agentIds"] == nil, let a = obj["agentId"] as? String { doc["agentIds"] = [a] }
                let data = try? JSONSerialization.data(withJSONObject: doc)
                if let data {
                    try? await store.putDoc(corpusId: corpus, collection: "instrument-catalog", id: key, body: data)
                    // Update index doc
                    var ids: [String] = []
                    if let idxData = try? await store.getDoc(corpusId: corpus, collection: "instrument-catalog", id: "instrument-catalog:index"),
                       let idxObj = try? JSONSerialization.jsonObject(with: idxData) as? [String: Any],
                       let arr = idxObj["ids"] as? [String] { ids = arr }
                    if !ids.contains(id) { ids.append(id) }
                    let idx = ["ids": ids]
                    if let idxData = try? JSONSerialization.data(withJSONObject: idx) {
                        try? await store.putDoc(corpusId: corpus, collection: "instrument-catalog", id: "instrument-catalog:index", body: idxData)
                    }
                }
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data ?? Data("{}".utf8))
            }
            return HTTPResponse(status: 404)
        }
        let server = NIOHTTPServer(kernel: kernel)
        do {
            let port = Int(env["CATALOG_PORT"] ?? env["PORT"] ?? "8041") ?? 8041
            _ = try await server.start(port: port)
            print("instrument-catalog listening on :\(port)")
        } catch {
            FileHandle.standardError.write(Data("[instrument-catalog] Failed: \(error)\n".utf8))
        }
        dispatchMain()
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
