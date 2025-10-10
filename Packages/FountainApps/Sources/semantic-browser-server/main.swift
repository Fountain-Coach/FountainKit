import Foundation
import SemanticBrowserService
import LauncherSignature
import FountainRuntime

verifyLauncherSignature()

func buildService() -> SemanticMemoryService { SemanticMemoryService() }

Task {
    let env = ProcessInfo.processInfo.environment
    let service = buildService()
    // Serve generated OpenAPI handlers via a lightweight NIO transport.
    let fallback: HTTPKernel = { req in
        if req.method == "GET" && req.path == "/metrics" {
            return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: Data("ok\n".utf8))
        }
        return HTTPResponse(status: 404)
    }
    let transport = NIOOpenAPIServerTransport(fallback: fallback)
    let api = SemanticBrowserOpenAPI(service: service)
    // Register generated handlers; use root prefix.
    try? api.registerHandlers(on: transport, serverURL: URL(string: "/")!)
    let server = NIOHTTPServer(kernel: transport.asKernel())
    let port = Int(env["SEMANTIC_BROWSER_PORT"] ?? env["PORT"] ?? "8007") ?? 8007
    _ = try? await server.start(port: port)
    print("semantic-browser listening on \(port)")
}
RunLoop.main.run()

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
