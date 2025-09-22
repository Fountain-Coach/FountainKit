import Foundation
import FountainRuntime
import ToolServerService
import LauncherSignature

verifyLauncherSignature()

let serviceKernel = ToolServerService.HTTPKernel(handlers: Handlers())
let kernel = HTTPKernel { request in
    if request.method == "GET" {
        if request.path == "/metrics" {
            let body = Data("tool_server_up 1\n".utf8)
            return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: body)
        }
        if request.path == "/_health" {
            let body = Data("{\"status\":\"ok\"}".utf8)
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: body)
        }
    }
    let serviceRequest = ToolServerService.HTTPRequest(
        method: request.method,
        path: request.path,
        headers: request.headers,
        body: request.body
    )
    let serviceResponse = try await serviceKernel.handle(serviceRequest)
    return HTTPResponse(
        status: serviceResponse.status,
        headers: serviceResponse.headers,
        body: serviceResponse.body
    )
}

let server = NIOHTTPServer(kernel: kernel)
let port = Int(ProcessInfo.processInfo.environment["PORT"] ?? "8012") ?? 8012

Task {
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
