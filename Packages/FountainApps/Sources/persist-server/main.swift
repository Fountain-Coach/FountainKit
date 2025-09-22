import Foundation
import Dispatch
import FountainRuntime
import FountainStoreClient
import LauncherSignature

verifyLauncherSignature()

let env = ProcessInfo.processInfo.environment
let corpusId = env["DEFAULT_CORPUS_ID"] ?? "tools-factory"
let port = Int(env["FOUNTAINSTORE_PORT"] ?? env["PORT"] ?? "8005") ?? 8005
let svc = FountainStoreClient(client: EmbeddedFountainStoreClient())
Task {
    await svc.ensureCollections(corpusId: corpusId)
    let kernel = makePersistKernel(service: svc)
    let server = NIOHTTPServer(kernel: kernel)
    do {
        _ = try await server.start(port: port)
        print("persist server listening on port \(port)")
    } catch {
        FileHandle.standardError.write(Data("[persist] Failed to start: \(error)\n".utf8))
    }
}
dispatchMain()

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
