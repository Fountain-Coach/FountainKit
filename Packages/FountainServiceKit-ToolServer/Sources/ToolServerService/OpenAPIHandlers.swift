import Foundation
import OpenAPIRuntime

public struct ToolServerOpenAPI: APIProtocol, @unchecked Sendable {
    let compose = DockerComposeManager()

    public init() {}

    // Return JSON object with stdout/stderr/exit_code
    private func execJSON(service: String, args: [String]) -> OpenAPIRuntime.OpenAPIObjectContainer? {
        do {
            let (code, out, err) = try compose.run(service: service, args: args)
            let json: [String: (any Sendable)?] = [
                "exit_code": Int(code),
                "stdout": String(data: out, encoding: .utf8) ?? "",
                "stderr": String(data: err, encoding: .utf8) ?? ""
            ]
            return try OpenAPIRuntime.OpenAPIObjectContainer(unvalidatedValue: json)
        } catch {
            return try? OpenAPIRuntime.OpenAPIObjectContainer(unvalidatedValue: [
                "exit_code": -1,
                "stderr": String(describing: error)
            ])
        }
    }

    public func runImageMagick(_ input: Operations.runImageMagick.Input) async throws -> Operations.runImageMagick.Output {
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        // Pass request_id into the container environment for traceability.
        let env: [String: String] = req.request_id.map { ["TS_REQUEST_ID": $0] } ?? [:]
        let result = try compose.run(service: "imagemagick", args: req.args ?? [], extraEnv: env)
        // Prefer returning stdout as octet-stream if available; fallback to JSON status.
        if !result.stdout.isEmpty {
            // Use undocumented payload to keep response flexible if runtime types differ.
            if let body = try? OpenAPIRuntime.OpenAPIValueContainer(unvalidatedValue: Array(result.stdout)) {
                return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload(body))
            }
        }
        if let body = execJSON(service: "imagemagick", args: req.args ?? []) {
            return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload(body))
        }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func runFFmpeg(_ input: Operations.runFFmpeg.Input) async throws -> Operations.runFFmpeg.Output {
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let env: [String: String] = req.request_id.map { ["TS_REQUEST_ID": $0] } ?? [:]
        if let body = execJSON(service: "ffmpeg", args: req.args ?? []) {
            return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload(body))
        }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func runExifTool(_ input: Operations.runExifTool.Input) async throws -> Operations.runExifTool.Output {
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let env: [String: String] = req.request_id.map { ["TS_REQUEST_ID": $0] } ?? [:]
        if let body = execJSON(service: "exiftool", args: req.args ?? []) {
            return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload(body))
        }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func runPandoc(_ input: Operations.runPandoc.Input) async throws -> Operations.runPandoc.Output {
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let env: [String: String] = req.request_id.map { ["TS_REQUEST_ID": $0] } ?? [:]
        if let body = execJSON(service: "pandoc", args: req.args ?? []) {
            return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload(body))
        }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func runLibPlist(_ input: Operations.runLibPlist.Input) async throws -> Operations.runLibPlist.Output {
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let env: [String: String] = req.request_id.map { ["TS_REQUEST_ID": $0] } ?? [:]
        if let body = execJSON(service: "libplist", args: req.args ?? []) {
            return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload(body))
        }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func pdfScan(_ input: Operations.pdfScan.Input) async throws -> Operations.pdfScan.Output {
        // Not dockerized yet; return stub OK.
        if let body = try? OpenAPIRuntime.OpenAPIObjectContainer(unvalidatedValue: ["status": "queued"]) {
            return .ok(.init(body: .json(body)))
        }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func pdfIndexValidate(_ input: Operations.pdfIndexValidate.Input) async throws -> Operations.pdfIndexValidate.Output {
        if let body = try? OpenAPIRuntime.OpenAPIObjectContainer(unvalidatedValue: ["ok": true, "issues": [] as [String]]) {
            return .ok(.init(body: .json(body)))
        }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func pdfQuery(_ input: Operations.pdfQuery.Input) async throws -> Operations.pdfQuery.Output {
        if let body = try? OpenAPIRuntime.OpenAPIObjectContainer(unvalidatedValue: ["hits": [] as [Any]]) {
            return .ok(.init(body: .json(body)))
        }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func pdfExportMatrix(_ input: Operations.pdfExportMatrix.Input) async throws -> Operations.pdfExportMatrix.Output {
        if let body = try? OpenAPIRuntime.OpenAPIObjectContainer(unvalidatedValue: [
            "schemaVersion": "1.0",
            "messages": [] as [Any],
            "terms": [] as [Any],
            "bitfields": [] as [Any],
            "ranges": [] as [Any],
            "enums": [] as [Any]
        ]) {
            return .ok(.init(body: .json(body)))
        }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }
}
