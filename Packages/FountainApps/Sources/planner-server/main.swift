import Foundation
import Dispatch
import FountainRuntime
import FountainStoreClient
import PlannerService
import LauncherSignature

verifyLauncherSignature()

let env = ProcessInfo.processInfo.environment
let corpusId = env["DEFAULT_CORPUS_ID"] ?? "tools-factory"
let svc = FountainStoreClient(client: EmbeddedFountainStoreClient())
Task {
    await svc.ensureCollections(corpusId: corpusId)
    // Register generated OpenAPI handlers via NIO bridge
    let transport = NIOOpenAPIServerTransport()
    let api = PlannerOpenAPI(persistence: svc)
    try? api.registerHandlers(on: transport, serverURL: URL(string: "/")!)
    let server = NIOHTTPServer(kernel: transport.asKernel())
    do {
        let port = Int(env["PLANNER_PORT"] ?? env["PORT"] ?? "8003") ?? 8003
        _ = try await server.start(port: port)
        print("planner server listening on port \(port)")
    } catch {
        FileHandle.standardError.write(Data("[planner] Failed to start: \(error)\n".utf8))
    }
}
dispatchMain()

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
