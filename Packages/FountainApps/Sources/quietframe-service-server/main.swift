import Foundation
import FountainRuntime
import quietframe_service

@main
struct Main {
    static func main() {
        let env = ProcessInfo.processInfo.environment
        let port = Int(env["QUIETFRAME_PORT"] ?? env["PORT"] ?? "7088") ?? 7088

        // Serve the spec at /openapi.yaml as a fallback route
        let fallback = HTTPKernel { req in
            if req.path == "/openapi.yaml" {
                let url = URL(fileURLWithPath: "Packages/FountainApps/Sources/quietframe-service/openapi.yaml")
                if let data = try? Data(contentsOf: url) {
                    return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
                }
            }
            return HTTPResponse(status: 404)
        }

        let transport = NIOOpenAPIServerTransport(fallback: fallback)
        do {
            try QuietframeServer.register(on: transport)
        } catch {
            FileHandle.standardError.write(Data("[quietframe-service] register failed: \(error)\n".utf8))
        }
        let server = NIOHTTPServer(kernel: transport.asKernel())

        let oneshot = (env["QUIETFRAME_ONESHOT"] == "1")
        if oneshot {
            Task {
                do {
                    var bound: Int
                    do {
                        bound = try await server.start(port: port)
                    } catch {
                        bound = try await server.start(port: 0)
                    }
                    print("quietframe-service bound on :\(bound) (one-shot mode)")
                    try? await server.stop()
                    exit(0)
                } catch {
                    FileHandle.standardError.write(Data("[quietframe-service] start failed: \(error)\n".utf8))
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
                        bound = try await server.start(port: 0)
                    }
                    print("quietframe-service listening on :\(bound)")
                } catch {
                    FileHandle.standardError.write(Data("[quietframe-service] failed to start: \(error)\n".utf8))
                }
            }
            dispatchMain()
        }
    }
}
