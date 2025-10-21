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
    // Serve generated OpenAPI handlers via NIO transport with a simple fallback.
    let fallback = HTTPKernel { req in
        if req.method == "GET" && req.path == "/metrics" {
            return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: Data("ok\n".utf8))
        }
        if req.method == "GET" && req.path == "/openapi.yaml" {
            let url = URL(fileURLWithPath: "Packages/FountainServiceKit-FunctionCaller/Sources/FunctionCallerService/openapi.yaml")
            if let data = try? Data(contentsOf: url) {
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
            }
        }
        return HTTPResponse(status: 404)
    }
    let transport = NIOOpenAPIServerTransport(fallback: fallback)
    let basePrefix = env["FUNCTION_CALLER_BASE_URL"]
    let api = FunctionCallerOpenAPI(persistence: svc, baseURLPrefix: basePrefix)
    try? api.registerHandlers(on: transport, serverURL: URL(string: "/")!)
    let server = NIOHTTPServer(kernel: transport.asKernel())
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
