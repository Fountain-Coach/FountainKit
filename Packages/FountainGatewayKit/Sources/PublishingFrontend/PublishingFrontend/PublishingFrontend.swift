import Foundation
import NIO
import NIOHTTP1
import FountainRuntime
import Yams
import FountainStoreClient

/// Configuration for the ``PublishingFrontend`` server.
public struct PublishingConfig: Codable {
    /// TCP port the server listens on.
    public var port: Int
    /// Directory containing static files served by the frontend.
    public var rootPath: String

    /// Creates a new configuration with optional port and root path.
    /// - Parameters:
    ///   - port: Port to bind the HTTP server to.
    ///   - rootPath: Directory containing static files to serve.
    public init(port: Int = 8085, rootPath: String = "./Public") {
        self.port = port
        self.rootPath = rootPath
    }
}

/// Lightweight HTTP server for serving generated documentation.
public final class PublishingFrontend {
    /// Underlying HTTP server handling requests.
    private let server: NIOHTTPServer
    /// Event loop group driving asynchronous operations.
    private let group: EventLoopGroup
    /// Runtime configuration specifying port and root path.
    private let config: PublishingConfig
    /// Actual port the server is bound to after start.
    public private(set) var port: Int

    /// Creates a new server instance with the given configuration.
    /// - Parameter config: Runtime configuration options.
    public init(config: PublishingConfig) {
        self.config = config
        self.port = config.port
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let kernel = HTTPKernel { [config] req in
            guard req.method == "GET" else { return HTTPResponse(status: 405) }
            let path = config.rootPath + (req.path == "/" ? "/index.html" : req.path)
            if let data = FileManager.default.contents(atPath: path) {
                let contentType = mimeType(forPath: path)
                var headers: [String:String] = [
                    "Content-Type": contentType,
                    // Strongly discourage browsers and proxies from caching while iterating fast.
                    "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
                    "Pragma": "no-cache",
                    "Expires": "0"
                ]
                if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                   let mdate = attrs[.modificationDate] as? Date {
                    let fmt = DateFormatter(); fmt.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'"; fmt.locale = Locale(identifier: "en_US_POSIX"); fmt.timeZone = TimeZone(secondsFromGMT: 0)
                    headers["Last-Modified"] = fmt.string(from: mdate)
                }
                return HTTPResponse(status: 200, headers: headers, body: data)
            }
            return HTTPResponse(status: 404)
        }
        self.server = NIOHTTPServer(kernel: kernel, group: group)
    }

    @MainActor
    /// Starts the HTTP server on the configured port.
    public func start() async throws {
        port = try await server.start(port: config.port)
        print("PublishingFrontend: serving \(config.rootPath) on :\(port)")
    }

    @MainActor
    /// Stops the HTTP server and releases all resources.
    public func stop() async throws {
        try await server.stop()
        try await group.shutdownGracefully()
    }
}

/// Loads the publishing configuration from FountainStore's `config/publishing.yml`.
/// Falls back to `Configuration/publishing.yml` when FountainStore is unavailable.
public func loadPublishingConfig(store: ConfigurationStore? = nil,
                                environment: [String: String] = ProcessInfo.processInfo.environment) throws -> PublishingConfig {
    let svc = store ?? ConfigurationStore.fromEnvironment(environment)
    if let data = svc?.getSync("publishing.yml"), let text = String(data: data, encoding: .utf8) {
        return try decodePublishingConfig(from: text)
    }
    let path = environment["PUBLISHING_CONFIG_PATH"] ?? "Configuration/publishing.yml"
    let raw = try String(contentsOfFile: path, encoding: .utf8)
    return try decodePublishingConfig(from: raw)
}

private func decodePublishingConfig(from raw: String) throws -> PublishingConfig {
    // Strip lines that begin with a copyright footer (e.g., starting with "©")
    // to keep configuration strictly YAML-parseable.
    let sanitized = raw
        .split(separator: "\n", omittingEmptySubsequences: false)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("©") }
        .joined(separator: "\n")
    let yaml = try Yams.load(yaml: sanitized) as? [String: Any] ?? [:]
    let defaults: [String: Any] = ["port": 8085, "rootPath": "./Public"]
    let merged = defaults.merging(yaml) { _, new in new }
    let data = try JSONSerialization.data(withJSONObject: merged)
    return try JSONDecoder().decode(PublishingConfig.self, from: data)
}

// Basic content-type resolution for common static assets.
func mimeType(forPath path: String) -> String {
    switch URL(fileURLWithPath: path).pathExtension.lowercased() {
    case "html", "htm": return "text/html"
    case "css": return "text/css"
    case "js": return "application/javascript"
    case "json": return "application/json"
    case "svg": return "image/svg+xml"
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    case "txt": return "text/plain"
    default: return "application/octet-stream"
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
