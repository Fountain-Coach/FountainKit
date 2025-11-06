import Foundation
import OpenAPIRuntime
import FountainRuntime

@main
struct Main {
    static func main() {
        let env = ProcessInfo.processInfo.environment
        let port = Int(env["MVK_RUNTIME_PORT"] ?? env["PORT"] ?? "7777") ?? 7777

        let fallback = HTTPKernel { req in
            // Serve the spec
            if req.path == "/openapi.yaml" {
                let url = URL(fileURLWithPath: "Packages/FountainApps/Sources/metalviewkit-runtime-server/openapi.yaml")
                if let data = try? Data(contentsOf: url) {
                    return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
                }
            }
            // SSE endpoints for near-live traces and backend events
            if req.path.hasPrefix("/v1/tracing/sse") {
                let traces = MetalViewKitRuntimeServer.sharedCore.traces.suffix(32)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.withoutEscapingSlashes]
                let blocks: [String] = traces.compactMap { ev in
                    if let data = try? encoder.encode(ev), let s = String(data: data, encoding: .utf8) {
                        return "data: \(s)\n\n"
                    }
                    return nil
                }
                let body = blocks.joined()
                return HTTPResponse(status: 200, headers: ["Content-Type": "text/event-stream", "X-Chunked-SSE": "1"], body: Data(body.utf8))
            }
            if req.path.hasPrefix("/v1/audio/backend/events-sse") {
                let s = MetalViewKitRuntimeServer.sharedCore.audio
                let obj: [String: Any] = [
                    "type": "backend.status",
                    "backend": s.backend.rawValue,
                    "streaming": s.streaming,
                    "deviceId": s.deviceId ?? "",
                    "sampleRate": s.sampleRate,
                    "blockFrames": s.blockFrames
                ]
                let data = try? JSONSerialization.data(withJSONObject: obj)
                let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                let body = "data: \(text)\n\n"
                return HTTPResponse(status: 200, headers: ["Content-Type": "text/event-stream", "X-Chunked-SSE": "1"], body: Data(body.utf8))
            }
            return HTTPResponse(status: 404)
        }

        let transport = NIOOpenAPIServerTransport(fallback: fallback)
        do { try MetalViewKitRuntimeServer.register(on: transport) } catch {
            FileHandle.standardError.write(Data("[mvk-runtime] register failed: \(error)\n".utf8))
        }
        let server = NIOHTTPServer(kernel: transport.asKernel())

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
    }
}

