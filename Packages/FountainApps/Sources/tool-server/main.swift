import Foundation
import FountainRuntime
import ToolServerService
import LauncherSignature

verifyLauncherSignature()

Task {
    let env = ProcessInfo.processInfo.environment
    if (env["TOOLSERVER_PULL_ON_START"] ?? "1") != "0" {
        let _ = try? ToolServerService.DockerComposeManager().pull()
    }
    let fallback = HTTPKernel { req in
        if req.method == "GET" && req.path == "/metrics" {
            return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: Data("tool_server_up 1\n".utf8))
        }
        if req.method == "GET" && req.path == "/_health" {
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: Data("{\"status\":\"ok\"}".utf8))
        }
        if req.method == "GET" && req.path == "/openapi.yaml" {
            let url = URL(fileURLWithPath: "Packages/FountainServiceKit-ToolServer/Sources/ToolServerService/openapi.yaml")
            if let data = try? Data(contentsOf: url) {
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
            }
        }
        return HTTPResponse(status: 404)
    }
    let transport = NIOOpenAPIServerTransport(fallback: fallback)
    let api = ToolServerOpenAPI()
    try? api.registerHandlers(on: transport, serverURL: URL(string: "/")!)
    let server = NIOHTTPServer(kernel: transport.asKernel())
    let port = Int(ProcessInfo.processInfo.environment["PORT"] ?? "8012") ?? 8012
    do {
        _ = try await server.start(port: port)
        print("tool-server listening on port \(port)")
    } catch {
        let message = "[tool-server] Failed to start: \(error)\n"
        FileHandle.standardError.write(Data(message.utf8))
    }
}

dispatchMain()

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
