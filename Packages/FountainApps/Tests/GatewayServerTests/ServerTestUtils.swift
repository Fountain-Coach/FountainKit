#if !ROBOT_ONLY
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FountainRuntime
@testable import gateway_server

enum ServerTestUtils {
    struct RunningServer {
        let server: GatewayServer
        let port: Int
        func stop() async { try? await server.stop() }
    }

    static func startGateway(on port: Int = 18111, plugins: [any GatewayPlugin] = []) async -> RunningServer {
        let server = await GatewayServer(plugins: plugins)
        do {
            let bound = try await server.startAndReturnPort(port: port)
            return RunningServer(server: server, port: bound)
        } catch {
            // Fallback to ephemeral port if the requested port is busy.
            let bound = (try? await server.startAndReturnPort(port: 0)) ?? port
            return RunningServer(server: server, port: bound)
        }
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

#endif // !ROBOT_ONLY
