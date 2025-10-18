import Foundation
import Dispatch
import FountainRuntime
import FountainStoreClient
import PersistService
import SpeechAtlasService
import LauncherSignature

verifyLauncherSignature()

let env = ProcessInfo.processInfo.environment
let corpusId = env["DEFAULT_CORPUS_ID"] ?? "tools-factory"
let port = Int(env["FOUNTAINSTORE_PORT"] ?? env["PORT"] ?? "8005") ?? 8005
func resolveStoreRoot(from env: [String: String]) -> URL {
    if let override = env["FOUNTAINSTORE_DIR"], !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let expanded: String
        if override.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            expanded = home + String(override.dropFirst())
        } else {
            expanded = override
        }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }
    // Default to repo-local data directory to make dev flows predictable
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    return cwd.appendingPathComponent(".fountain/store", isDirectory: true)
}

let svc: FountainStoreClient = {
    let root = resolveStoreRoot(from: env)
    do {
        let disk = try DiskFountainStoreClient(rootDirectory: root)
        print("persist: using disk store at \(root.path)")
        return FountainStoreClient(client: disk)
    } catch {
        FileHandle.standardError.write(Data("[persist] WARN: falling back to in-memory store (\(error))\n".utf8))
        return FountainStoreClient(client: EmbeddedFountainStoreClient())
    }
}()
Task {
    await svc.ensureCollections(corpusId: corpusId)
    // Prefer generated OpenAPI handlers; keep /metrics via fallback kernel
    let fallback = HTTPKernel { req in
        if req.method == "GET" && req.path == "/metrics" { return await metrics_metrics_get() }
        return HTTPResponse(status: 404)
    }
    let transport = NIOOpenAPIServerTransport(fallback: fallback)
    let api = PersistOpenAPI(persistence: svc)
    try? api.registerHandlers(on: transport, serverURL: URL(string: "/")!)
    let speechAtlas = SpeechAtlasHandlers(store: svc)
    try? speechAtlas.registerHandlers(on: transport, serverURL: URL(string: "/arcs/the-four-stars")!)
    let server = NIOHTTPServer(kernel: transport.asKernel())
    do {
        _ = try await server.start(port: port)
        print("persist server listening on port \(port)")
    } catch {
        FileHandle.standardError.write(Data("[persist] Failed to start: \(error)\n".utf8))
    }
}
dispatchMain()

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
