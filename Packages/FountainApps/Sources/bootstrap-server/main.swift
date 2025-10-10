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
    // Bridge generated OpenAPI handlers via NIO transport with a small fallback.
    let fallback = HTTPKernel { req in
        if req.method == "GET" && req.path == "/metrics" {
            return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: Data("ok\n".utf8))
        }
        if req.method == "GET" && req.path == "/openapi.yaml" {
            let url = URL(fileURLWithPath: "Packages/FountainServiceKit-Bootstrap/Sources/BootstrapService/openapi.yaml")
            if let data = try? Data(contentsOf: url) {
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
            }
        }
        return HTTPResponse(status: 404)
    }

    let transport = NIOOpenAPIServerTransport(fallback: fallback)
    let api = BootstrapOpenAPI(persistence: svc)
    try? api.registerHandlers(on: transport, serverURL: URL(string: "/")!)

    let server = NIOHTTPServer(kernel: transport.asKernel())
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
