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
let _ = Task {
    await svc.ensureCollections(corpusId: corpusId)
    // Wrap kernel to serve the curated OpenAPI spec for discovery
    let inner = makeFunctionCallerKernel(service: svc)
    let kernel: HTTPKernel = { req in
        if req.method == "GET" && req.path == "/openapi.yaml" {
            let url = URL(fileURLWithPath: "Packages/FountainSpecCuration/openapi/v1/function-caller.yml")
            if let data = try? Data(contentsOf: url) {
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
            }
        }
        return try await inner.handle(req)
    }
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
