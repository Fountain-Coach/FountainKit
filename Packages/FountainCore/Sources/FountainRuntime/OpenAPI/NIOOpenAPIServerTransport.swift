import Foundation
#if canImport(OpenAPIRuntime)
import OpenAPIRuntime
import HTTPTypes

/// SwiftNIO-friendly ServerTransport that bridges generated handlers into FountainRuntime's HTTPKernel.
public final class NIOOpenAPIServerTransport: ServerTransport, @unchecked Sendable {
    public typealias Handler = @Sendable (
        HTTPTypes.HTTPRequest,
        OpenAPIRuntime.HTTPBody?,
        OpenAPIRuntime.ServerRequestMetadata
    ) async throws -> (HTTPTypes.HTTPResponse, OpenAPIRuntime.HTTPBody?)

    private struct Route: Sendable {
        let method: HTTPTypes.HTTPRequest.Method
        let components: [PathComponent]
        let handler: Handler
    }

    private enum PathComponent: Sendable {
        case literal(String)
        case variable(String)
    }

    private var routes: [Route] = []
    private let fallback: HTTPKernel?

    /// Initialize a transport.
    /// - Parameter fallback: Optional fallback kernel for non‑OpenAPI routes (e.g. /metrics).
    public init(fallback: HTTPKernel? = nil) {
        self.fallback = fallback
    }

    /// Register a generated operation.
    public func register(
        _ handler: @Sendable @escaping (
            HTTPTypes.HTTPRequest,
            OpenAPIRuntime.HTTPBody?,
            OpenAPIRuntime.ServerRequestMetadata
        ) async throws -> (HTTPTypes.HTTPResponse, OpenAPIRuntime.HTTPBody?),
        method: HTTPTypes.HTTPRequest.Method,
        path: String
    ) throws {
        let comps = NIOOpenAPIServerTransport.parse(path)
        routes.append(Route(method: method, components: comps, handler: handler))
    }

    /// Expose as FountainRuntime HTTPKernel for use with `NIOHTTPServer`.
    public func asKernel() -> HTTPKernel {
        return HTTPKernel { [routes, fallback] req in
            // Convert request to HTTPTypes + metadata and attempt route match.
            guard let method = HTTPTypes.HTTPRequest.Method(rawValue: req.method) else {
                return HTTPResponse(status: 405)
            }
            let pathOnly: String = {
                if let idx = req.path.firstIndex(of: "?") { return String(req.path[..<idx]) }
                return req.path
            }()
            let segments = pathOnly.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            for route in routes where route.method == method {
                if let params = NIOOpenAPIServerTransport.match(segments: segments, to: route.components) {
                    var fields = HTTPFields()
                    for (k, v) in req.headers {
                        if let name = HTTPField.Name(k) { fields.append(HTTPField(name: name, value: v)) }
                    }
                    let httpReq = HTTPTypes.HTTPRequest(method: method, scheme: nil, authority: nil, path: req.path, headerFields: fields)
                    // Build HTTPBody if non-empty.
                    let body: HTTPBody? = req.body.isEmpty ? nil : HTTPBody(req.body)
                    let meta = ServerRequestMetadata(pathParameters: params)
                    do {
                        let (httpResp, httpBody) = try await route.handler(httpReq, body, meta)
                        // Translate back to FountainRuntime.HTTPResponse
                        var headers: [String: String] = [:]
                        for field in httpResp.headerFields { headers[field.name.description] = field.value }
                        let data: Data = await {
                            guard let httpBody else { return Data() }
                            // Collect with a sane upper bound (2MB) to avoid unbounded buffering.
                            if let d = try? await Data(collecting: httpBody, upTo: 2 * 1024 * 1024) { return d }
                            return Data()
                        }()
                        return HTTPResponse(status: Int(httpResp.status.code), headers: headers, body: data)
                    } catch {
                        return HTTPResponse(status: 500, headers: ["Content-Type": "text/plain"], body: Data("internal error".utf8))
                    }
                }
            }
            if let fb = fallback { return try await fb.handle(req) }
            return HTTPResponse(status: 404)
        }
    }

    // MARK: - Path helpers

    private static func parse(_ path: String) -> [PathComponent] {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return trimmed.split(separator: "/", omittingEmptySubsequences: true).map { seg in
            if seg.hasPrefix("{") && seg.hasSuffix("}") {
                return .variable(String(seg.dropFirst().dropLast()))
            }
            return .literal(String(seg))
        }
    }

    private static func match(segments: [String], to components: [PathComponent]) -> [String: Substring]? {
        guard segments.count == components.count else { return nil }
        var params: [String: Substring] = [:]
        for (seg, comp) in zip(segments, components) {
            switch comp {
            case .literal(let lit):
                if seg != lit { return nil }
            case .variable(let name):
                params[name] = Substring(seg)
            }
        }
        return params
    }
}

#endif
