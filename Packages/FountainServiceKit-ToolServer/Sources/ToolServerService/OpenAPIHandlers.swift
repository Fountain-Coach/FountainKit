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

    public func get_status(_ input: Operations.get_status.Input) async throws -> Operations.get_status.Output {
        let available = compose.available()
        var services: [[String: (any Sendable)?]] = []
        if available {
            if let (code, out, _) = try? compose.ps(json: true), code == 0,
               let jsonArray = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]] {
                for item in jsonArray {
                    let name = (item["Service"] as? String) ?? (item["Name"] as? String) ?? ""
                    let state = (item["State"] as? String) ?? (item["Status"] as? String) ?? "unknown"
                    let running = state.lowercased().contains("running") || state.lowercased().contains("up")
                    let container = item["ID"] as? String
                    let image = item["Image"] as? String
                    services.append([
                        "name": name,
                        "running": running,
                        "container": container as (any Sendable)?,
                        "image": image as (any Sendable)?,
                        "state": state
                    ])
                }
            }
        }
        let dict: [String: (any Sendable)?] = [
            "available": available,
            "project": compose.projectName,
            "compose_file": compose.composeFile,
            "workdir": compose.workdir,
            "timeout_sec": compose.timeoutSec,
            "services": services
        ]
        if let container = try? OpenAPIRuntime.OpenAPIObjectContainer(unvalidatedValue: dict) {
            return .ok(.init(body: .json(container)))
        }
        return .undocumented(statusCode: 200, OpenAPIRuntime.UndocumentedPayload())
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
