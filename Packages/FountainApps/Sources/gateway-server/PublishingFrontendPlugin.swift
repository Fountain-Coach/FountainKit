import Foundation
import FountainRuntime

/// Serves static files from disk when requests are not handled elsewhere.
public struct PublishingFrontendPlugin: GatewayPlugin {
    /// Directory on disk containing files to be served.
    let rootPath: String

    /// Creates a new plugin pointing at the given directory.
    public init(rootPath: String = "./Public") {
        self.rootPath = rootPath
    }

    /// Attempts to serve a static file for GET requests that resulted in `404`.
    /// - Parameters:
    ///   - response: Upstream response, typically `404` from the router.
    ///   - request: Incoming HTTP request to resolve.
    /// - Returns: Either the original response or a `200` with file contents. When a file is served the `Content-Type` header is set to `text/html`.
    public func respond(_ response: HTTPResponse, for request: HTTPRequest) async throws -> HTTPResponse {
        guard request.method == "GET" else { return response }
        let path = rootPath + (request.path == "/" ? "/index.html" : request.path)
        if let data = FileManager.default.contents(atPath: path) {
            let contentType = mimeType(forPath: path)
            return HTTPResponse(status: 200, headers: ["Content-Type": contentType], body: data)
        }
        return response
    }
}

private func mimeType(forPath path: String) -> String {
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
