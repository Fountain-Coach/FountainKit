import Foundation
import FountainStoreClient
import BootstrapService
import FountainRuntime
import LauncherSignature

verifyLauncherSignature()

let env = ProcessInfo.processInfo.environment
let corpusId = env["DEFAULT_CORPUS_ID"] ?? "tools-factory"
let svc = FountainStoreClient(client: EmbeddedFountainStoreClient())
Task {
    await svc.ensureCollections(corpusId: corpusId)
    let server = NIOHTTPServer(kernel: makeBootstrapKernel(service: svc))
    do {
        let port = Int(env["BOOTSTRAP_PORT"] ?? env["PORT"] ?? "8002") ?? 8002
        _ = try await server.start(port: port)
        print("bootstrap (NIO) listening on :\(port)")
    } catch {
        FileHandle.standardError.write(Data("[bootstrap] Failed to start: \(error)\n".utf8))
    }
}
dispatchMain()

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
