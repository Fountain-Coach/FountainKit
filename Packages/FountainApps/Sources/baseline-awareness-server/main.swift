import Foundation
import FountainStoreClient
import AwarenessService
import FountainRuntime
import LauncherSignature

verifyLauncherSignature()

let env = ProcessInfo.processInfo.environment
let corpusId = env["DEFAULT_CORPUS_ID"] ?? "tools-factory"
let svc = FountainStoreClient(client: EmbeddedFountainStoreClient())
Task {
    // Serve curated OpenAPI spec for discovery alongside the service kernel
    let inner = makeAwarenessKernel(service: svc)
    let kernel: HTTPKernel = { req in
        if req.method == "GET" && req.path == "/openapi.yaml" {
            let url = URL(fileURLWithPath: "Packages/FountainSpecCuration/openapi/v1/baseline-awareness.yml")
            if let data = try? Data(contentsOf: url) {
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
            }
        }
        return try await inner.handle(req)
    }
    let server = NIOHTTPServer(kernel: kernel)
    do {
        let port = Int(env["BASELINE_AWARENESS_PORT"] ?? env["PORT"] ?? "8001") ?? 8001
        _ = try await server.start(port: port)
        print("baseline-awareness (NIO) listening on :\(port)")
    } catch {
        FileHandle.standardError.write(Data("[baseline-awareness] Failed to start: \(error)\n".utf8))
    }
}
dispatchMain()

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
