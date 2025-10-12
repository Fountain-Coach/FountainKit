import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FountainRuntime
import FountainStoreClient

/// Collection of request handlers used by ``LLMGatewayPlugin``.
public struct Handlers: Sendable {
    private enum Backend {
        case local(LocalAgentClient)
        case openAI(OpenAIConfig)

        var label: String {
            switch self {
            case .local: return "local-agent"
            case .openAI: return "openai"
            }
        }
    }

    private let backend: Backend
    private let session: URLSession
    private let metrics: MetricsRecorder

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let defaultSession = URLSession.shared
        if let backendName = environment["LLM_BACKEND"]?.lowercased(),
           (backendName == "openai" || backendName == "open-ai"),
           let apiKey = environment["OPENAI_API_KEY"], !apiKey.isEmpty {
            let endpoint = URL(string: environment["OPENAI_API_ENDPOINT"] ?? "https://api.openai.com/v1/chat/completions") ?? URL(string: "https://api.openai.com/v1/chat/completions")!
            let model = environment["OPENAI_MODEL"] ?? "gpt-4o-mini"
            let temperature = Double(environment["OPENAI_TEMPERATURE"] ?? "")
            let topP = Double(environment["OPENAI_TOP_P"] ?? "")
            let timeout = TimeInterval(Double(environment["OPENAI_TIMEOUT_SECONDS"] ?? "") ?? 20)
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = timeout
            configuration.timeoutIntervalForResource = timeout + 10
            configuration.httpAdditionalHeaders = ["Accept": "application/json"]
            let openAISession = URLSession(configuration: configuration)
            self.session = openAISession
            self.backend = .openAI(.init(apiKey: apiKey,
                                         endpoint: endpoint,
                                         model: model,
                                         temperature: temperature,
                                         topP: topP,
                                         timeout: timeout))
        } else {
            self.backend = .local(LocalAgentClient())
            self.session = defaultSession
        }
        self.metrics = MetricsRecorder(backendLabel: backend.label)
    }

    public init() {
        self.init(environment: ProcessInfo.processInfo.environment)
    }

    /// Forwards chat requests to the configured backend.
    public func chatWithObjective(_ request: HTTPRequest, body: ChatRequest) async throws -> HTTPResponse {
        switch backend {
        case .local(let client):
            let response = try await handleLocalAgent(request: request, body: body, client: client)
            await metrics.recordSuccess()
            return response
        case .openAI(let config):
            do {
                let response = try await handleOpenAI(request: request, body: body, config: config)
                await metrics.recordSuccess()
                return response
            } catch {
                await metrics.recordFailure(error.localizedDescription)
                return makeErrorResponse(message: error.localizedDescription)
            }
        }
    }

    /// Prometheus style metrics endpoint.
    public func metrics_metrics_get() async -> HTTPResponse {
        let uptime = Int(ProcessInfo.processInfo.systemUptime)
        let snapshot = await metrics.snapshot()
        var body = "llm_gateway_uptime_seconds \(uptime)\n"
        body += "llm_gateway_backend_info{backend=\"\(snapshot.label)\"} 1\n"
        body += "llm_gateway_requests_total \(snapshot.successes + snapshot.failures)\n"
        body += "llm_gateway_requests_failed_total \(snapshot.failures)\n"
        if let lastError = snapshot.lastError {
            let sanitized = lastError.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
            body += "# llm_gateway_last_error \(sanitized)\n"
        }
        return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: Data(body.utf8))
    }

    // MARK: - Backend Implementations

    private func handleLocalAgent(request: HTTPRequest, body: ChatRequest, client: LocalAgentClient) async throws -> HTTPResponse {
        if client.config.inprocessMode {
            let data = try LocalCoreMLAdapter(modelPath: client.config.coreml_model).respond(to: body)
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
        }

        let useStream = request.path.contains("stream=1") || client.config.use_stream
        let endpoint = useStream ? client.config.stream_endpoint : client.config.chat_endpoint
        let url = URL(string: endpoint, relativeTo: client.config.base_url)?.absoluteURL ?? client.config.base_url
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 200
        var headers: [String: String] = [:]
        if let http = resp as? HTTPURLResponse, let contentType = http.allHeaderFields["Content-Type"] as? String {
            headers["Content-Type"] = contentType
        } else {
            headers["Content-Type"] = useStream ? "text/event-stream" : "application/json"
        }
        return HTTPResponse(status: status, headers: headers, body: data)
    }

    private func handleOpenAI(request: HTTPRequest, body: ChatRequest, config: OpenAIConfig) async throws -> HTTPResponse {
        var payload: [String: Any] = [
            "model": config.model,
            "messages": body.messages.map { ["role": $0.role, "content": $0.content] }
        ]

        if let functions = body.functions, !functions.isEmpty {
            payload["functions"] = functions.map { fn -> [String: Any] in
                var dict: [String: Any] = ["name": fn.name]
                if let description = fn.description { dict["description"] = description }
                return dict
            }
        }

        if let functionCall = body.function_call {
            switch functionCall {
            case .auto:
                payload["function_call"] = "auto"
            case .named(let obj):
                payload["function_call"] = ["name": obj.name]
            }
        }

        if let temperature = config.temperature { payload["temperature"] = temperature }
        if let topP = config.topP { payload["top_p"] = topP }

        var req = URLRequest(url: config.endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        req.timeoutInterval = config.timeout

        log("[llm] \(backend.label) request started model=\(config.model)")
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 500

        guard (200...299).contains(status) else {
            let message = String(data: data, encoding: .utf8) ?? "OpenAI request failed"
            return makeErrorResponse(status: status, message: message, raw: message)
        }

        let responseObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] ?? [:]
        let transformed = transformOpenAIResponse(responseObject: responseObject, config: config)
        let responseData = try JSONSerialization.data(withJSONObject: transformed, options: [.sortedKeys])
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: responseData)
    }

    private func transformOpenAIResponse(responseObject: [String: Any], config: OpenAIConfig) -> [String: Any] {
        var answer: String = ""
        var functionCall: [String: Any]?

        if let choices = responseObject["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any] {
            if let content = message["content"] as? String {
                answer = content
            }
            if let call = message["function_call"] as? [String: Any] {
                functionCall = call
            }
        }

        var transformed: [String: Any] = [
            "answer": answer,
            "provider": "openai",
            "model": config.model,
            "raw": responseObject
        ]

        if let functionCall {
            transformed["function_call"] = functionCall
        }

        if let usage = responseObject["usage"] {
            transformed["usage"] = usage
        }

        return transformed
    }

    private func makeErrorResponse(status: Int = 502, message: String, raw: String? = nil) -> HTTPResponse {
        log("[llm] \(backend.label) error status=\(status) message=\(message)")
        var payload: [String: Any] = [
            "error": message,
            "provider": backend.label,
            "status": status == 0 ? 502 : status
        ]
        if let raw { payload["raw_error"] = raw }
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data(message.utf8)
        return HTTPResponse(status: status == 0 ? 502 : status, headers: ["Content-Type": "application/json"], body: data)
    }
}

private struct OpenAIConfig: Sendable {
    let apiKey: String
    let endpoint: URL
    let model: String
    let temperature: Double?
    let topP: Double?
    let timeout: TimeInterval
}

private actor MetricsRecorder {
    let label: String
    private var successes: Int = 0
    private var failures: Int = 0
    private var lastError: String?

    init(backendLabel: String) {
        self.label = backendLabel
    }

    func recordSuccess() {
        successes += 1
        lastError = nil
    }

    func recordFailure(_ message: String) {
        failures += 1
        lastError = message
    }

    func snapshot() -> (label: String, successes: Int, failures: Int, lastError: String?) {
        (label: label, successes: successes, failures: failures, lastError: lastError)
    }
}

@inline(__always)
private func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
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
