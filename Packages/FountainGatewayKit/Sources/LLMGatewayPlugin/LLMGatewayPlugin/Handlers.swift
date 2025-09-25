import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FountainRuntime
import FountainStoreClient

/// Collection of request handlers used by ``LLMGatewayPlugin``.
public struct Handlers: Sendable {
    private let client: LocalAgentClient

    public init() {
        self.client = LocalAgentClient()
    }

    /// Forwards chat requests to the configured LocalAgent service.
    public func chatWithObjective(_ request: HTTPRequest, body: ChatRequest) async throws -> HTTPResponse {
        // Choose in-process vs HTTP based on configuration store/file
        if client.config.inprocessMode {
            let data = try LocalCoreMLAdapter(modelPath: client.config.coreml_model).respond(to: body)
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
        } else {
            let useStream = request.path.contains("stream=1") || client.config.use_stream
            let endpoint = useStream ? client.config.stream_endpoint : client.config.chat_endpoint
            let url = URL(string: endpoint, relativeTo: client.config.base_url)?.absoluteURL ?? client.config.base_url
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 200
            var headers: [String: String] = [:]
            if let http = resp as? HTTPURLResponse, let contentType = http.allHeaderFields["Content-Type"] as? String {
                headers["Content-Type"] = contentType
            } else {
                headers["Content-Type"] = useStream ? "text/event-stream" : "application/json"
            }
            return HTTPResponse(status: status, headers: headers, body: data)
        }
    }

    /// Prometheus style metrics endpoint.
    public func metrics_metrics_get() async -> HTTPResponse {
        let uptime = Int(ProcessInfo.processInfo.systemUptime)
        let body = Data("llm_gateway_uptime_seconds \(uptime)\n".utf8)
        return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: body)
    }
}

// MARK: - LocalAgent configuration and client

private struct LocalAgentConfig: Codable {
    var base_url: URL
    var chat_endpoint: String
    var stream_endpoint: String
    var use_stream: Bool
    var mode: String?
    var coreml_model: String?

    static let `default` = LocalAgentConfig(
        base_url: URL(string: "http://127.0.0.1:8080")!,
        chat_endpoint: "/chat",
        stream_endpoint: "/chat/stream",
        use_stream: false,
        mode: nil,
        coreml_model: nil
    )
}

private struct LocalAgentClient {
    let config: LocalAgentConfig

    init() {
        self.config = Self.loadConfig()
    }

    private static func loadConfig() -> LocalAgentConfig {
        // 1) Try ConfigurationStore (control plane preferred)
        if let store = ConfigurationStore.fromEnvironment(),
           let data = store.getSync("local-agent/config.json") {
            if let cfg = try? JSONDecoder().decode(LocalAgentConfig.self, from: data) { return cfg }
        }
        // 2) Fallback to repository configuration file
        let cwd = FileManager.default.currentDirectoryPath
        let file = URL(fileURLWithPath: cwd).appendingPathComponent("Configuration/local-agent.json")
        if let data = try? Data(contentsOf: file) {
            if let cfg = try? JSONDecoder().decode(LocalAgentConfig.self, from: data) { return cfg }
            // Backward/alternative config shape support
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let host = (obj["host"] as? String) ?? "127.0.0.1"
                let port = (obj["port"] as? Int) ?? 8080
                let base = URL(string: "http://\(host):\(port)") ?? LocalAgentConfig.default.base_url
                let chat = (obj["chat_endpoint"] as? String) ?? "/chat"
                let stream = (obj["stream_endpoint"] as? String) ?? "/chat/stream"
                let useStream = (obj["use_stream"] as? Bool) ?? false
                let mode = (obj["mode"] as? String)
                let model = (obj["coreml_model"] as? String)
                return LocalAgentConfig(base_url: base, chat_endpoint: chat, stream_endpoint: stream, use_stream: useStream, mode: mode, coreml_model: model)
            }
        }
        // 3) Defaults
        return .default
    }
}

private extension LocalAgentConfig {
    var inprocessMode: Bool {
        guard let m = mode?.lowercased() else { return false }
        return m == "inprocess" || m == "coreml" || m == "local"
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
