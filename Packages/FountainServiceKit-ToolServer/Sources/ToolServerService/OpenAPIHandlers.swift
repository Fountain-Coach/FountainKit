import Foundation
import OpenAPIRuntime
import HTTPTypes

public struct ToolServerOpenAPI: APIProtocol, @unchecked Sendable {
    let compose = DockerComposeManager()

    public init() {}

    private struct ToolCommandResult: Codable, Sendable {
        let exit_code: Int
        let stdout: String?
        let stderr: String?
    }

    // Return JSON object with stdout/stderr/exit_code
    private func execJSON(
        service: String,
        args: [String],
        env: [String: String] = [:]
    ) -> OpenAPIRuntime.UndocumentedPayload? {
        func encode(_ result: ToolCommandResult) throws -> OpenAPIRuntime.UndocumentedPayload {
            let data = try JSONEncoder().encode(result)
            var headers = HTTPFields()
            headers[.contentType] = "application/json"
            return OpenAPIRuntime.UndocumentedPayload(
                headerFields: headers,
                body: OpenAPIRuntime.HTTPBody(data)
            )
        }

        do {
            let (code, out, err) = try compose.run(service: service, args: args, extraEnv: env)
            let result = ToolCommandResult(
                exit_code: Int(code),
                stdout: String(data: out, encoding: .utf8),
                stderr: String(data: err, encoding: .utf8)
            )
            return try encode(result)
        } catch {
            let failure = ToolCommandResult(exit_code: -1, stdout: nil, stderr: String(describing: error))
            return try? encode(failure)
        }
    }

    public func get_status(_ input: Operations.get_status.Input) async throws -> Operations.get_status.Output {
        let available = compose.available()
        var services: [Components.Schemas.ServiceStatus] = []
        if available {
            if let (code, out, _) = try? compose.ps(json: true), code == 0,
               let jsonArray = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]] {
                for item in jsonArray {
                    let name = (item["Service"] as? String) ?? (item["Name"] as? String) ?? ""
                    let state = (item["State"] as? String) ?? (item["Status"] as? String) ?? "unknown"
                    let running = state.lowercased().contains("running") || state.lowercased().contains("up")
                    let container = item["ID"] as? String
                    let image = item["Image"] as? String
                    services.append(
                        .init(
                            name: name,
                            running: running,
                            container: container,
                            image: image,
                            state: state
                        )
                    )
                }
            }
        }
        let status = Components.Schemas.ComposeStatus(
            available: available,
            project: compose.projectName,
            compose_file: compose.composeFile,
            workdir: compose.workdir,
            timeout_sec: compose.timeoutSec,
            services: services.isEmpty ? nil : services
        )
        return .ok(.init(body: .json(status)))
    }

    public func runImageMagick(_ input: Operations.runImageMagick.Input) async throws -> Operations.runImageMagick.Output {
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        // Pass request_id into the container environment for traceability.
        let env: [String: String] = req.request_id.map { ["TS_REQUEST_ID": $0] } ?? [:]
        let result = try compose.run(service: "imagemagick", args: req.args, extraEnv: env)
        // Prefer returning stdout as octet-stream if available; fallback to JSON status.
        if !result.stdout.isEmpty {
            // Use undocumented payload to keep response flexible if runtime types differ.
            return .ok(.init(body: .binary(OpenAPIRuntime.HTTPBody(result.stdout))))
        }
        if let payload = execJSON(service: "imagemagick", args: req.args, env: env) {
            return .undocumented(statusCode: 200, payload)
        }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func runFFmpeg(_ input: Operations.runFFmpeg.Input) async throws -> Operations.runFFmpeg.Output {
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let env: [String: String] = req.request_id.map { ["TS_REQUEST_ID": $0] } ?? [:]
        if let payload = execJSON(service: "ffmpeg", args: req.args, env: env) {
            return .undocumented(statusCode: 200, payload)
        }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func runExifTool(_ input: Operations.runExifTool.Input) async throws -> Operations.runExifTool.Output {
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let env: [String: String] = req.request_id.map { ["TS_REQUEST_ID": $0] } ?? [:]
        if let payload = execJSON(service: "exiftool", args: req.args, env: env) {
            return .undocumented(statusCode: 200, payload)
        }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func runPandoc(_ input: Operations.runPandoc.Input) async throws -> Operations.runPandoc.Output {
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let env: [String: String] = req.request_id.map { ["TS_REQUEST_ID": $0] } ?? [:]
        if let payload = execJSON(service: "pandoc", args: req.args, env: env) {
            return .undocumented(statusCode: 200, payload)
        }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func runLibPlist(_ input: Operations.runLibPlist.Input) async throws -> Operations.runLibPlist.Output {
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let env: [String: String] = req.request_id.map { ["TS_REQUEST_ID": $0] } ?? [:]
        if let payload = execJSON(service: "libplist", args: req.args, env: env) {
            return .undocumented(statusCode: 200, payload)
        }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
    }

    public func pdfScan(_ input: Operations.pdfScan.Input) async throws -> Operations.pdfScan.Output {
        // Not dockerized yet; return stub OK.
        let index = Components.Schemas.Index(documents: [])
        return .ok(.init(body: .json(index)))
    }

    public func pdfIndexValidate(_ input: Operations.pdfIndexValidate.Input) async throws -> Operations.pdfIndexValidate.Output {
        let result = Components.Schemas.ValidationResult(ok: true, issues: [])
        return .ok(.init(body: .json(result)))
    }

    public func pdfQuery(_ input: Operations.pdfQuery.Input) async throws -> Operations.pdfQuery.Output {
        let response = Components.Schemas.QueryResponse(hits: [])
        return .ok(.init(body: .json(response)))
    }

    public func pdfExportMatrix(_ input: Operations.pdfExportMatrix.Input) async throws -> Operations.pdfExportMatrix.Output {
        let emptyEntries: [Components.Schemas.MatrixEntry] = []
        let matrix = Components.Schemas.Matrix(
            schemaVersion: "1.0",
            messages: emptyEntries,
            terms: emptyEntries,
            bitfields: [],
            ranges: [],
            enums: []
        )
        return .ok(.init(body: .json(matrix)))
    }
}
