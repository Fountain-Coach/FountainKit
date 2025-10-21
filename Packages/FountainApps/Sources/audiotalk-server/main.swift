import Foundation
import Dispatch
import FountainRuntime
import AudioTalkService
import LauncherSignature

verifyLauncherSignature()

let env = ProcessInfo.processInfo.environment

Task {
    // Serve generated OpenAPI handlers via NIO bridge with fallback that serves the spec
    let fallback = HTTPKernel { req in
        if req.path == "/openapi.yaml" {
            let url = URL(fileURLWithPath: "Packages/FountainServiceKit-AudioTalk/Sources/AudioTalkService/openapi.yaml")
            if let data = try? Data(contentsOf: url) {
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
            }
        }
        return HTTPResponse(status: 404)
    }
    let transport = NIOOpenAPIServerTransport(fallback: fallback)
    let api = AudioTalkOpenAPI(state: AudioTalkState())
    try? api.registerHandlers(on: transport, serverURL: URL(string: "/")!)
    let server = NIOHTTPServer(kernel: transport.asKernel())
    do {
        let port = Int(env["AUDIOTALK_PORT"] ?? env["PORT"] ?? "8080") ?? 8080
        _ = try await server.start(port: port)
        print("audiotalk-server listening on port \(port)")
    } catch {
        FileHandle.standardError.write(Data("[audiotalk] Failed to start: \(error)\n".utf8))
    }
}
dispatchMain()

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
