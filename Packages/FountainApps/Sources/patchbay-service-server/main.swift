import Foundation
import FountainRuntime
import patchbay_service

@main
struct Main {
    static func main() {
        let env = ProcessInfo.processInfo.environment
        let port = Int(env["PATCHBAY_PORT"] ?? env["PORT"] ?? "7090") ?? 7090

        // Serve the spec at /openapi.yaml as a fallback route
        let fallback = HTTPKernel { req in
            if req.path == "/openapi.yaml" {
                let url = URL(fileURLWithPath: "Packages/FountainApps/Sources/patchbay-service/openapi.yaml")
                if let data = try? Data(contentsOf: url) {
                    return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
                }
            }
            return HTTPResponse(status: 404)
        }

        let transport = NIOOpenAPIServerTransport(fallback: fallback)
        do {
            try PatchBayServer.register(on: transport)
        } catch {
            FileHandle.standardError.write(Data("[patchbay-service] register failed: \(error)\n".utf8))
        }
        let server = NIOHTTPServer(kernel: transport.asKernel())

        let oneshot = (env["PATCHBAY_ONESHOT"] == "1")
        if oneshot {
            Task {
                do {
                    var bound: Int
                    do {
                        bound = try await server.start(port: port)
                    } catch {
                        // Retry on ephemeral port if preferred port is busy
                        bound = try await server.start(port: 0)
                    }
                    print("patchbay-service bound on :\(bound) (one-shot mode)")
                    try? await server.stop()
                    exit(0)
                } catch {
                    FileHandle.standardError.write(Data("[patchbay-service] start failed: \(error)\n".utf8))
                    exit(2)
                }
            }
            dispatchMain()
        } else {
            Task {
                do {
                    var bound: Int
                    do {
                        bound = try await server.start(port: port)
                    } catch {
                        // Fallback: bind on an ephemeral port when preferred port is busy
                        bound = try await server.start(port: 0)
                    }
                    print("patchbay-service listening on :\(bound)")
                } catch {
                    FileHandle.standardError.write(Data("[patchbay-service] failed to start: \(error)\n".utf8))
                }
            }
            dispatchMain()
        }
    }
}
