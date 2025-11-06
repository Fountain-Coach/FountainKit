import Foundation
import OpenAPIRuntime
import FountainRuntime
import MetalViewKitRuntimeServerKit

let env = ProcessInfo.processInfo.environment
let port = Int(env["MVK_RUNTIME_PORT"] ?? env["PORT"] ?? "7777") ?? 7777

let fallback = HTTPKernel { req in
    // Serve curated spec via local $ref file
    if req.path == "/openapi.yaml" {
        let url = URL(fileURLWithPath: "Packages/FountainApps/Sources/MetalViewKitRuntimeServerKit/openapi.yaml")
        if let data = try? Data(contentsOf: url) {
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
        }
        return HTTPResponse(status: 404)
    }

    // SSE: tracing events
    if req.path.split(separator: "?").first == "/v1/tracing/sse" {
        // Emit current trace array repeatedly as SSE frames
        let line = "data: \(MetalViewKitRuntimeServer.tracingJSON())\n\n"
        // Simulate streaming with multiple chunks
        let body = Data(Array(repeating: line, count: 10).joined().utf8)
        return HTTPResponse(status: 200,
                            headers: [
                                "Content-Type": "text/event-stream",
                                // Signal the server to chunk and flush pieces progressively
                                "X-Chunked-SSE": "1"
                            ],
                            body: body)
    }

    // SSE: audio backend events
    if req.path.split(separator: "?").first == "/v1/audio/backend/events-sse" {
        let line = "data: \(MetalViewKitRuntimeServer.backendEventJSON())\n\n"
        let body = Data(Array(repeating: line, count: 20).joined().utf8)
        return HTTPResponse(status: 200,
                            headers: [
                                "Content-Type": "text/event-stream",
                                "X-Chunked-SSE": "1"
                            ],
                            body: body)
    }

    return HTTPResponse(status: 404)
}

let transport = NIOOpenAPIServerTransport(fallback: fallback)
do { try MetalViewKitRuntimeServer.register(on: transport) } catch {
    FileHandle.standardError.write(Data("[mvk-runtime] register failed: \(error)\n".utf8))
}
// WebSocket routes: tracing stream and backend events
let ws: [String: @Sendable () -> String] = [
    "/v1/tracing/stream": { MetalViewKitRuntimeServer.tracingJSON() },
    "/v1/audio/backend/events": { MetalViewKitRuntimeServer.backendEventJSON() }
]
let sse: [String: @Sendable () -> String] = [
    "/v1/tracing/sse": { MetalViewKitRuntimeServer.tracingJSON() },
    "/v1/audio/backend/events-sse": { MetalViewKitRuntimeServer.backendEventJSON() }
]
let server = NIOHTTPServer(kernel: transport.asKernel(), webSocketRoutes: ws, sseRoutes: sse)

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
