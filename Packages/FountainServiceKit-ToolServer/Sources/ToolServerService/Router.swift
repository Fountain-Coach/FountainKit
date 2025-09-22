import Foundation

public struct Router {
    public var handlers: Handlers

    public init(handlers: Handlers = Handlers()) {
        self.handlers = handlers
    }

    public func route(_ request: HTTPRequest) async throws -> HTTPResponse {
        let decoder = JSONDecoder()
        switch (request.method, request.path) {
        case ("POST", "/ffmpeg"):
            let body = try? decoder.decode(ToolRequest.self, from: request.body)
            return try await handlers.runffmpeg(request, body: body)
        case ("POST", "/exiftool"):
            let body = try? decoder.decode(ToolRequest.self, from: request.body)
            return try await handlers.runexiftool(request, body: body)
        case ("POST", "/imagemagick"):
            let body = try? decoder.decode(ToolRequest.self, from: request.body)
            return try await handlers.runimagemagick(request, body: body)
        case ("POST", "/pdf/scan"):
            let body = try? decoder.decode(ScanRequest.self, from: request.body)
            return try await handlers.pdfscan(request, body: body)
        case ("POST", "/pandoc"):
            let body = try? decoder.decode(ToolRequest.self, from: request.body)
            return try await handlers.runpandoc(request, body: body)
        case ("POST", "/pdf/export-matrix"):
            let body = try? decoder.decode(ExportMatrixRequest.self, from: request.body)
            return try await handlers.pdfexportmatrix(request, body: body)
        case ("POST", "/libplist"):
            let body = try? decoder.decode(ToolRequest.self, from: request.body)
            return try await handlers.runlibplist(request, body: body)
        case ("POST", "/pdf/query"):
            let body = try? decoder.decode(QueryRequest.self, from: request.body)
            return try await handlers.pdfquery(request, body: body)
        case ("POST", "/pdf/index/validate"):
            let body = try? decoder.decode(Index.self, from: request.body)
            return try await handlers.pdfindexvalidate(request, body: body)
        default:
            let paths: Set<String> = [
                "/ffmpeg",
                "/exiftool",
                "/imagemagick",
                "/pdf/scan",
                "/pandoc",
                "/pdf/export-matrix",
                "/libplist",
                "/pdf/query",
                "/pdf/index/validate"
            ]
            if paths.contains(request.path) {
                return HTTPResponse(
                    status: 405,
                    headers: ["Content-Type": "text/plain", "Allow": "POST"],
                    body: Data("Method Not Allowed".utf8)
                )
            } else {
                return HTTPResponse(
                    status: 404,
                    headers: ["Content-Type": "text/plain"],
                    body: Data("Not Found".utf8)
                )
            }
        }
    }
}

extension Router: @unchecked Sendable {}
// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
