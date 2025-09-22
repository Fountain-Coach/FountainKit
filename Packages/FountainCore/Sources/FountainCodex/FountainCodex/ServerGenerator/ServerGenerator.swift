import Foundation

/// Generates a lightweight Swift server from an ``OpenAPISpec``.
public enum ServerGenerator {
    /// Generates server sources for the supplied specification.
    /// - Parameters:
    ///   - spec: Parsed OpenAPI document.
    ///   - url: Destination directory for generated sources.
    public static func emitServer(from spec: OpenAPISpec, to url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try emitHTTPRequest(to: url)
        try emitHTTPResponse(to: url)
        try emitHTTPServer(to: url)
        try emitHandlers(from: spec, to: url)
        try emitRouter(from: spec, to: url)
        try emitKernel(to: url)
    }

    /// Writes a minimal `HTTPRequest` type used by generated servers.
    /// - Parameter url: Directory to place the generated source file in.
    private static func emitHTTPRequest(to url: URL) throws {
        let output = """
        import Foundation

        public struct NoBody: Codable {}

        public struct HTTPRequest {
            public let method: String
            public let path: String
            public var headers: [String: String]
            public var body: Data

            public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
                self.method = method
                self.path = path
                self.headers = headers
                self.body = body
            }
        }
        """
        try (output + "\n").write(to: url.appendingPathComponent("HTTPRequest.swift"), atomically: true, encoding: .utf8)
    }

    /// Writes a minimal `HTTPResponse` type used by generated servers.
    /// - Parameter url: Directory to place the generated source file in.
    private static func emitHTTPResponse(to url: URL) throws {
        let output = """
        import Foundation

        public struct HTTPResponse {
            public var status: Int
            public var headers: [String: String]
            public var body: Data

            public init(status: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
                self.status = status
                self.headers = headers
                self.body = body
            }
        }
        """
        try (output + "\n").write(to: url.appendingPathComponent("HTTPResponse.swift"), atomically: true, encoding: .utf8)
    }

    /// Emits a default `Handlers` struct with stubs for each operation.
    /// - Parameters:
    ///   - spec: Source specification describing server operations.
    ///   - url: Directory where the file should be generated.
    private static func emitHandlers(from spec: OpenAPISpec, to url: URL) throws {
        var output = "import Foundation\n\npublic struct Handlers {\n    public init() {}\n"
        if let paths = spec.paths {
            for (_, item) in paths {
                if let op = item.get {
                    output += "    public func \(op.operationId.camelCased)(_ request: HTTPRequest, body: \(bodyType(for: op))?) async throws -> HTTPResponse {\n        return HTTPResponse(status: 501, headers: [\"Content-Type\": \"text/plain\"], body: Data(\"not implemented\".utf8))\n    }\n"
                }
                if let op = item.post {
                    output += "    public func \(op.operationId.camelCased)(_ request: HTTPRequest, body: \(bodyType(for: op))?) async throws -> HTTPResponse {\n        return HTTPResponse(status: 501, headers: [\"Content-Type\": \"text/plain\"], body: Data(\"not implemented\".utf8))\n    }\n"
                }
                if let op = item.put {
                    output += "    public func \(op.operationId.camelCased)(_ request: HTTPRequest, body: \(bodyType(for: op))?) async throws -> HTTPResponse {\n        return HTTPResponse(status: 501, headers: [\"Content-Type\": \"text/plain\"], body: Data(\"not implemented\".utf8))\n    }\n"
                }
                if let op = item.delete {
                    output += "    public func \(op.operationId.camelCased)(_ request: HTTPRequest, body: \(bodyType(for: op))?) async throws -> HTTPResponse {\n        return HTTPResponse(status: 501, headers: [\"Content-Type\": \"text/plain\"], body: Data(\"not implemented\".utf8))\n    }\n"
                }
            }
        }
        output += "}\n"
        try output.write(to: url.appendingPathComponent("Handlers.swift"), atomically: true, encoding: .utf8)
    }

    /// Emits a routing table that dispatches requests to generated handlers.
    /// - Parameters:
    ///   - spec: Source specification describing paths and methods.
    ///   - url: Directory where the file should be generated.
    private static func emitRouter(from spec: OpenAPISpec, to url: URL) throws {
        var output = "import Foundation\n\npublic struct Router {\n    public var handlers: Handlers\n\n    public init(handlers: Handlers = Handlers()) {\n        self.handlers = handlers\n    }\n\n    public func route(_ request: HTTPRequest) async throws -> HTTPResponse {\n        switch (request.method, request.path) {\n"
        if let paths = spec.paths {
            for (path, item) in paths {
                if let op = item.get {
                    output += "        case (\"GET\", \"\(path)\"):\n            let body = try? JSONDecoder().decode(\(bodyType(for: op)).self, from: request.body)\n            return try await handlers.\(op.operationId.camelCased)(request, body: body)\n"
                }
                if let op = item.post {
                    output += "        case (\"POST\", \"\(path)\"):\n            let body = try? JSONDecoder().decode(\(bodyType(for: op)).self, from: request.body)\n            return try await handlers.\(op.operationId.camelCased)(request, body: body)\n"
                }
                if let op = item.put {
                    output += "        case (\"PUT\", \"\(path)\"):\n            let body = try? JSONDecoder().decode(\(bodyType(for: op)).self, from: request.body)\n            return try await handlers.\(op.operationId.camelCased)(request, body: body)\n"
                }
                if let op = item.delete {
                    output += "        case (\"DELETE\", \"\(path)\"):\n            let body = try? JSONDecoder().decode(\(bodyType(for: op)).self, from: request.body)\n            return try await handlers.\(op.operationId.camelCased)(request, body: body)\n"
                }
            }
        }
        output += "        default:\n            return HTTPResponse(status: 404)\n        }\n    }\n}\n"
        try output.write(to: url.appendingPathComponent("Router.swift"), atomically: true, encoding: .utf8)
    }

    /// Emits an `HTTPKernel` that wires the router into a service boundary.
    /// - Parameter url: Directory to place the generated source file in.
    private static func emitKernel(to url: URL) throws {
        let output = """
        import Foundation

        public struct HTTPKernel {
            let router: Router

            public init(handlers: Handlers = Handlers()) {
                self.router = Router(handlers: handlers)
            }

            public func handle(_ request: HTTPRequest) async throws -> HTTPResponse {
                try await router.route(request)
            }
        }
        """
        try (output + "\n").write(to: url.appendingPathComponent("HTTPKernel.swift"), atomically: true, encoding: .utf8)
    }

    /// Emits a lightweight `URLProtocol`-based HTTP server for testing.
    /// - Parameter url: Directory to place the generated source file in.
    private static func emitHTTPServer(to url: URL) throws {
        let output = """
        import Foundation

        public class HTTPServer: URLProtocol {
            static var kernel: HTTPKernel?

            public static func register(kernel: HTTPKernel) {
                self.kernel = kernel
                URLProtocol.registerClass(HTTPServer.self)
            }

            public override class func canInit(with request: URLRequest) -> Bool {
                request.url?.host == "localhost"
            }

            public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

            override public func startLoading() {
                guard let kernel = HTTPServer.kernel, let url = request.url else {
                    client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                    return
                }
                let req = HTTPRequest(method: request.httpMethod ?? "GET", path: url.path, headers: request.allHTTPHeaderFields ?? [:], body: request.httpBody ?? Data())
                let strongSelf = self
                Task { @Sendable in
                    do {
                        let resp = try await kernel.handle(req)
                        let httpResponse = HTTPURLResponse(url: url, statusCode: resp.status, httpVersion: "HTTP/1.1", headerFields: resp.headers)!
                        client?.urlProtocol(strongSelf, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
                        client?.urlProtocol(strongSelf, didLoad: resp.body)
                        client?.urlProtocolDidFinishLoading(strongSelf)
                    } catch {
                        client?.urlProtocol(strongSelf, didFailWithError: error)
                    }
                }
            }

            override public func stopLoading() {}
        }

        extension HTTPServer: @unchecked Sendable {}
        """
        try (output + "\n").write(to: url.appendingPathComponent("HTTPServer.swift"), atomically: true, encoding: .utf8)
    }

    /// Determines the Swift type used for an operation's request body.
    private static func bodyType(for op: OpenAPISpec.Operation) -> String {
        guard let schema = op.requestBody?.content["application/json"]?.schema else {
            return "NoBody"
        }
        if schema.ref == nil {
            return "\(op.operationId)Request"
        }
        return schema.swiftType
    }
}

extension String {
    /// Returns the string converted from `snake_case` to `camelCase`.
    /// Words are split on underscores with the first word lowercased and
    /// remaining words capitalized before joining them together.
    /// Empty segments from leading, trailing, or consecutive underscores are
    /// ignored, and numeric segments remain unchanged to preserve identifiers
    /// like `api_v2`.
    var camelCased: String {
        guard !isEmpty else { return self }
        // Break the identifier into components separated by underscores.
        let parts = split(separator: "_")
        // Lowercase the first component and capitalize the remaining ones.
        guard let first = parts.first else { return self }
        let rest = parts.dropFirst().map { $0.capitalized }
        // Recombine the parts into a single camelCase string.
        return ([first.lowercased()] + rest).joined()
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
