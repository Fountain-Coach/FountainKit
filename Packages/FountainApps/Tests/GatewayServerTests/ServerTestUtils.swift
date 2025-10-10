import Foundation
import FountainRuntime
@testable import gateway_server

enum ServerTestUtils {
    struct RunningServer {
        let server: GatewayServer
        let port: Int
        func stop() async { try? await server.stop() }
    }

    static func startGateway(on port: Int = 18111) async -> RunningServer {
        let server = GatewayServer()
        try? await server.start(port: port)
        return RunningServer(server: server, port: port)
    }

    static func httpJSON(_ method: String, _ url: URL, headers: [String: String] = [:], body: Any? = nil) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            if req.value(forHTTPHeaderField: "Content-Type") == nil {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        let (d, r) = try await URLSession.shared.data(for: req)
        return (d, r as! HTTPURLResponse)
    }
}

