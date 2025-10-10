import Foundation
import Dispatch
import FountainRuntime
import FountainStoreClient
import PersistService
import LauncherSignature

verifyLauncherSignature()

let env = ProcessInfo.processInfo.environment
let corpusId = env["DEFAULT_CORPUS_ID"] ?? "tools-factory"
let port = Int(env["FOUNTAINSTORE_PORT"] ?? env["PORT"] ?? "8005") ?? 8005
let svc = FountainStoreClient(client: EmbeddedFountainStoreClient())
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
