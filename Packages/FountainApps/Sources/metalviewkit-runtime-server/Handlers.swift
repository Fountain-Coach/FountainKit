import Foundation
import OpenAPIRuntime

final class MVKRuntimeHandlers: APIProtocol, @unchecked Sendable {
    // Minimal health implementation to get the server compiling; expand alongside handlers.
    func getHealth(_ input: Operations.getHealth.Input) async throws -> Operations.getHealth.Output {
        let uptime = ProcessInfo.processInfo.systemUptime
        return .ok(.init(body: .json(.init(status: .ok, uptimeSec: uptime))))
    }
}

