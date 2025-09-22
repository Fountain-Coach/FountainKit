@_exported import ToolServer
import Foundation
import FountainRuntime
import FountainStoreClient

public struct HTTPRequest: Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data
    public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data
    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

public final class ToolsFactoryRouter: @unchecked Sendable {
    private let router: ToolServer.Router
    public init(service: FountainStoreClient?, adapters: [String: ToolAdapter], manifest: ToolManifest, defaultCorpusId: String = ProcessInfo.processInfo.environment["TOOLS_FACTORY_CORPUS_ID"] ?? "tools-factory") {
        self.router = ToolServer.Router(adapters: adapters, manifest: manifest, persistence: service, defaultCorpusId: defaultCorpusId)
    }
    /// `GET /metrics`
    public func metrics_metrics_get() async throws -> HTTPResponse {
        let uptime = Int(ProcessInfo.processInfo.systemUptime)
        let body = Data("tools_factory_uptime_seconds \(uptime)\n".utf8)
        return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: body)
    }

    public func route(_ request: HTTPRequest) async throws -> HTTPResponse {
        if request.method == "GET" {
            if request.path == "/openapi.yaml" {
                let url = URL(fileURLWithPath: "openapi/v1/tools-factory.yml")
                let data = try Data(contentsOf: url)
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
            }
            if request.path == "/metrics" {
                return try await metrics_metrics_get()
            }
        }
        let ar = ToolServer.HTTPRequest(method: request.method, path: request.path, headers: request.headers, body: request.body)
        let resp = try await router.route(ar)
        return HTTPResponse(status: resp.status, headers: resp.headers, body: resp.body)
    }
}

public func makeToolsFactoryKernel(service svc: FountainStoreClient?, adapters: [String: ToolAdapter], manifest: ToolManifest) -> HTTPKernel {
    let router = ToolsFactoryRouter(service: svc, adapters: adapters, manifest: manifest)
    return HTTPKernel { req in
        let ar = HTTPRequest(method: req.method, path: req.path, headers: req.headers, body: req.body)
        let resp = try await router.route(ar)
        return FountainRuntime.HTTPResponse(status: resp.status, headers: resp.headers, body: resp.body)
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
