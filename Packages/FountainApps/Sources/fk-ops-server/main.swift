import Foundation
import FountainRuntime
import FKOpsService
import LauncherSignature

verifyLauncherSignature()

Task {
    let fallback = HTTPKernel { req in
        if req.method == "GET" && req.path == "/openapi.yaml" {
            let url = URL(fileURLWithPath: "Packages/FountainServiceKit-FKOps/Sources/FKOpsService/openapi.yaml")
            if let data = try? Data(contentsOf: url) { return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data) }
        }
        return HTTPResponse(status: 404)
    }
    let transport = NIOOpenAPIServerTransport(fallback: fallback)
    let api = FKOpsOpenAPI()
    try? api.registerHandlers(on: transport, serverURL: URL(string: "/")!)
    let server = NIOHTTPServer(kernel: transport.asKernel())
    let port = Int(ProcessInfo.processInfo.environment["FK_OPS_PORT"] ?? "8020") ?? 8020
    _ = try? await server.start(port: port)
    print("fk-ops-server listening on port \(port)")
}
RunLoop.main.run()

