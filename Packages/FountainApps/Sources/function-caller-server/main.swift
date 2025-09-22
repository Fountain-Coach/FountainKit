import Foundation
import Dispatch
import FountainRuntime
import FountainStoreClient
import FunctionCallerService
import LauncherSignature

verifyLauncherSignature()

let env = ProcessInfo.processInfo.environment
let corpusId = env["DEFAULT_CORPUS_ID"] ?? "tools-factory"
let svc = FountainStoreClient(client: EmbeddedFountainStoreClient())
Task {
    await svc.ensureCollections(corpusId: corpusId)
    let kernel = makeFunctionCallerKernel(service: svc)
    let server = NIOHTTPServer(kernel: kernel)
    do {
        let port = Int(env["FUNCTION_CALLER_PORT"] ?? env["PORT"] ?? "8004") ?? 8004
        _ = try await server.start(port: port)
        print("function-caller server listening on port \(port)")
    } catch {
        FileHandle.standardError.write(Data("[function-caller] Failed to start: \(error)\n".utf8))
    }
}
dispatchMain()

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
