import Foundation
import LauncherSignature
import FountainRuntime
import SemanticBrowserService

verifyLauncherSignature()

func buildService() -> SemanticMemoryService { SemanticMemoryService() }

let _ = Task {
    let env = ProcessInfo.processInfo.environment
    let service = buildService()
    // Serve generated OpenAPI handlers via a lightweight NIO transport.
    let fallback: HTTPKernel = { req in
        if req.method == "GET" && req.path == "/metrics" {
            return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: Data("ok\n".utf8))
        }
        if req.method == "GET" && req.path == "/openapi.yaml" {
            let url = URL(fileURLWithPath: "Packages/FountainServiceKit-SemanticBrowser/Sources/SemanticBrowserService/openapi.yaml")
            if let data = try? Data(contentsOf: url) {
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
            }
        }
        return HTTPResponse(status: 404)
    }
    // Choose engine based on environment
    let engine: BrowserEngine = {
        if let ws = env["SB_CDP_URL"], let u = URL(string: ws) { return CDPBrowserEngine(wsURL: u) }
        if let bin = env["SB_BROWSER_CLI"] {
            return ShellBrowserEngine(
                binary: bin,
                args: (env["SB_BROWSER_ARGS"] ?? "").split(separator: " ").map(String.init)
            )
        }
        return URLFetchBrowserEngine()
    }()
    let transport = NIOOpenAPIServerTransport(fallback: fallback)
    let api = SemanticBrowserOpenAPI(service: service, engine: engine)
    // Register generated handlers; use root prefix.
    try? api.registerHandlers(on: transport, serverURL: URL(string: "/")!)
    let server = NIOHTTPServer(kernel: transport.asKernel())
    let port = Int(env["SEMANTIC_BROWSER_PORT"] ?? env["PORT"] ?? "8007") ?? 8007
    _ = try? await server.start(port: port)
    print("semantic-browser listening on \(port)")
}
RunLoop.main.run()

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
