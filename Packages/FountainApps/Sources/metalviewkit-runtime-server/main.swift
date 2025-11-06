import Foundation
import OpenAPIRuntime
import FountainRuntime
import MetalViewKitRuntimeServerKit

let env = ProcessInfo.processInfo.environment
let port = Int(env["MVK_RUNTIME_PORT"] ?? env["PORT"] ?? "7777") ?? 7777

let fallback = HTTPKernel { req in
            // Serve the spec only
            if req.path == "/openapi.yaml" {
                let url = URL(fileURLWithPath: "Packages/FountainApps/Sources/MetalViewKitRuntimeServerKit/openapi.yaml")
                if let data = try? Data(contentsOf: url) {
                    return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
                }
            }
            return HTTPResponse(status: 404)
}

let transport = NIOOpenAPIServerTransport(fallback: fallback)
do { try MetalViewKitRuntimeServer.register(on: transport) } catch {
    FileHandle.standardError.write(Data("[mvk-runtime] register failed: \(error)\n".utf8))
}
let ws: [String: @Sendable () -> String] = [:]
let server = NIOHTTPServer(kernel: transport.asKernel(), webSocketRoutes: ws)

Task {
    do {
        var bound: Int
        do { bound = try await server.start(port: port) } catch { bound = try await server.start(port: 0) }
        print("metalviewkit-runtime listening on :\(bound)")
    } catch {
        FileHandle.standardError.write(Data("[mvk-runtime] failed to start: \(error)\n".utf8))
        exit(2)
    }
}
dispatchMain()
