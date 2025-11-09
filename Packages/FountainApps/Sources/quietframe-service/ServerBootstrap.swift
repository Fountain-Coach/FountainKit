import Foundation
import OpenAPIRuntime

struct QuietFrameServerBootstrap {
    static func defaultServerConfiguration() -> (host: String, port: Int) {
        let env = ProcessInfo.processInfo.environment
        let host = env["HOST"] ?? "127.0.0.1"
        let port = Int(env["QUIETFRAME_PORT"] ?? env["PORT"] ?? "7088") ?? 7088
        return (host, port)
    }
}

public enum QuietframeServer {
    public static func register(on transport: any ServerTransport) throws {
        let handlers = Operations.Server()
        try handlers.registerHandlers(on: transport, serverURL: URL(string: "/")!)
    }
}
