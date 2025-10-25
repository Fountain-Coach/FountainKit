import Foundation
import FountainRuntime
import qc_mock_service

@main
struct Main {
    static func main() {
        let env = ProcessInfo.processInfo.environment
        let port = Int(env["QC_MOCK_PORT"] ?? env["PORT"] ?? "7088") ?? 7088

        // Serve the spec at /openapi.yaml as a fallback route
        let fallback = HTTPKernel { req in
            if req.path == "/openapi.yaml" {
                let url = URL(fileURLWithPath: "Packages/FountainApps/Sources/qc-mock-service/openapi.yaml")
                if let data = try? Data(contentsOf: url) {
                    return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
                }
            }
            return HTTPResponse(status: 404)
        }

        let transport = NIOOpenAPIServerTransport(fallback: fallback)
        do {
            try QCMockServer.register(on: transport)
        } catch {
            FileHandle.standardError.write(Data("[qc-mock-service] register failed: \(error)\n".utf8))
        }
        let server = NIOHTTPServer(kernel: transport.asKernel())

        Task {
            do {
                _ = try await server.start(port: port)
                print("qc-mock-service listening on :\(port)")
            } catch {
                FileHandle.standardError.write(Data("[qc-mock-service] failed to start: \(error)\n".utf8))
            }
        }
        dispatchMain()
    }
}

