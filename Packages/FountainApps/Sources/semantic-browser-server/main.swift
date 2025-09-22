import Foundation
import SemanticBrowserService
import LauncherSignature

verifyLauncherSignature()

func buildService() -> SemanticMemoryService { SemanticMemoryService() }

Task {
    let env = ProcessInfo.processInfo.environment
    let service = buildService()
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
    let requireKey = (env["SB_REQUIRE_API_KEY"] ?? "true").lowercased() != "false"
    let kernel = makeSemanticKernel(service: service, engine: engine, requireAPIKey: requireKey)
    let server = NIOHTTPServer(kernel: kernel)
    let port = Int(env["SEMANTIC_BROWSER_PORT"] ?? env["PORT"] ?? "8007") ?? 8007
    _ = try? await server.start(port: port)
    print("semantic-browser listening on \(port)")
}
RunLoop.main.run()

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
