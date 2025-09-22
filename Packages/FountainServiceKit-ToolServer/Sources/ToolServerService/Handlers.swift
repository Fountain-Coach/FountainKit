import Foundation
import ToolServer

public struct Handlers {
    private let ffmpegAdapter: ToolAdapter
    private let exifToolAdapter: ToolAdapter
    private let imageMagickAdapter: ToolAdapter
    private let pandocAdapter: ToolAdapter
    private let libPlistAdapter: ToolAdapter
    private let pdfScanAdapter: ToolAdapter
    private let pdfQueryAdapter: ToolAdapter
    private let pdfExportMatrixAdapter: ToolAdapter

    public init(
        ffmpegAdapter: ToolAdapter = FFmpegAdapter(),
        exifToolAdapter: ToolAdapter = ExifToolAdapter(),
        imageMagickAdapter: ToolAdapter = ImageMagickAdapter(),
        pandocAdapter: ToolAdapter = PandocAdapter(),
        libPlistAdapter: ToolAdapter = LibPlistAdapter(),
        pdfScanAdapter: ToolAdapter = PDFScanAdapter(),
        pdfQueryAdapter: ToolAdapter = PDFQueryAdapter(),
        pdfExportMatrixAdapter: ToolAdapter = PDFExportMatrixAdapter()
    ) {
        self.ffmpegAdapter = ffmpegAdapter
        self.exifToolAdapter = exifToolAdapter
        self.imageMagickAdapter = imageMagickAdapter
        self.pandocAdapter = pandocAdapter
        self.libPlistAdapter = libPlistAdapter
        self.pdfScanAdapter = pdfScanAdapter
        self.pdfQueryAdapter = pdfQueryAdapter
        self.pdfExportMatrixAdapter = pdfExportMatrixAdapter
    }

    public func runffmpeg(_ request: HTTPRequest, body: ToolRequest?) async throws -> HTTPResponse {
        guard let body else { return HTTPResponse(status: 400) }
        let (data, code) = try ffmpegAdapter.run(args: body.args)
        return HTTPResponse(status: Int(code == 0 ? 200 : 500), body: data)
    }

    public func runexiftool(_ request: HTTPRequest, body: ToolRequest?) async throws -> HTTPResponse {
        guard let body else { return HTTPResponse(status: 400) }
        let (data, code) = try exifToolAdapter.run(args: body.args)
        return HTTPResponse(status: Int(code == 0 ? 200 : 500), body: data)
    }

    public func runimagemagick(_ request: HTTPRequest, body: ToolRequest?) async throws -> HTTPResponse {
        guard let body else { return HTTPResponse(status: 400) }
        let (data, code) = try imageMagickAdapter.run(args: body.args)
        return HTTPResponse(status: Int(code == 0 ? 200 : 500), headers: ["Content-Type": "application/octet-stream"], body: data)
    }

    public func pdfscan(_ request: HTTPRequest, body: ScanRequest?) async throws -> HTTPResponse {
        guard let body else { return HTTPResponse(status: 400) }
        let input = try JSONEncoder().encode(body)
        let arg = String(data: input, encoding: .utf8) ?? ""
        let (data, code) = try pdfScanAdapter.run(args: [arg])
        guard code == 0 else { return HTTPResponse(status: 500, body: data) }
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    public func runpandoc(_ request: HTTPRequest, body: ToolRequest?) async throws -> HTTPResponse {
        guard let body else { return HTTPResponse(status: 400) }
        let (data, code) = try pandocAdapter.run(args: body.args)
        return HTTPResponse(status: Int(code == 0 ? 200 : 500), body: data)
    }

    public func pdfexportmatrix(_ request: HTTPRequest, body: ExportMatrixRequest?) async throws -> HTTPResponse {
        guard let body else { return HTTPResponse(status: 400) }
        let input = try JSONEncoder().encode(body)
        let arg = String(data: input, encoding: .utf8) ?? ""
        let (data, code) = try pdfExportMatrixAdapter.run(args: [arg])
        guard code == 0 else { return HTTPResponse(status: 500, body: data) }
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    public func runlibplist(_ request: HTTPRequest, body: ToolRequest?) async throws -> HTTPResponse {
        guard let body else { return HTTPResponse(status: 400) }
        let (data, code) = try libPlistAdapter.run(args: body.args)
        return HTTPResponse(status: Int(code == 0 ? 200 : 500), body: data)
    }

    public func pdfquery(_ request: HTTPRequest, body: QueryRequest?) async throws -> HTTPResponse {
        guard let body else { return HTTPResponse(status: 400) }
        let input = try JSONEncoder().encode(body)
        let arg = String(data: input, encoding: .utf8) ?? ""
        let (data, code) = try pdfQueryAdapter.run(args: [arg])
        guard code == 0 else { return HTTPResponse(status: 500, body: data) }
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    public func pdfindexvalidate(_ request: HTTPRequest, body: Index?) async throws -> HTTPResponse {
        guard body != nil else { return HTTPResponse(status: 400) }
        let resp = ValidationResult(issues: [], ok: true)
        let data = try JSONEncoder().encode(resp)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }
}

extension Handlers: @unchecked Sendable {}
// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
