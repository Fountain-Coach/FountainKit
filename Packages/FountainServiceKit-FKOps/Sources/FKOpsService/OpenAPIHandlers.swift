import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import OpenAPIRuntime

public struct FKOpsOpenAPI: APIProtocol, @unchecked Sendable {
    public init() {}

    private func ack(_ ok: Bool, _ msg: String? = nil) -> Components.Schemas.Ack {
        .init(ok: ok, message: msg)
    }

    // Helper: run a shell command and capture output.
    private func run(_ launchPath: String, _ args: [String] = [], cwd: String? = nil, timeout: TimeInterval = 60) -> (ok: Bool, out: String, err: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        if let cwd { proc.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let outPipe = Pipe(); let errPipe = Pipe()
        proc.standardOutput = outPipe; proc.standardError = errPipe
        let group = DispatchGroup(); group.enter()
        proc.terminationHandler = { _ in group.leave() }
        do { try proc.run() } catch { return (false, "", String(describing: error)) }
        _ = group.wait(timeout: .now() + timeout)
        if proc.isRunning { proc.terminate() }
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (proc.terminationStatus == 0, out, err)
    }

    private func ping(_ url: URL, timeout: TimeInterval = 1.0) async -> Bool {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        let session = URLSession(configuration: config)
        do {
            let (_, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse { return (200...399).contains(http.statusCode) }
        } catch { }
        return false
    }

    public func fkStatus(_ input: Operations.fkStatus.Input) async throws -> Operations.fkStatus.Output {
        let host = "127.0.0.1"
        let targets: [(String, Int, String, String)] = [
            ("gateway", 8010, "/metrics", "/openapi.yaml"),
            ("baseline-awareness", 8001, "/metrics", "/openapi.yaml"),
            ("bootstrap", 8002, "/metrics", "/openapi.yaml"),
            ("planner", 8003, "/metrics", "/openapi.yaml"),
            ("function-caller", 8004, "/metrics", "/openapi.yaml"),
            ("persist", 8005, "/metrics", "/openapi.yaml"),
            ("semantic-browser", 8007, "/metrics", "/openapi.yaml"),
            ("tools-factory", 8011, "/metrics", "/openapi.yaml"),
            ("tool-server", 8012, "/_status", "/openapi.yaml")
        ]
        var services: [Components.Schemas.ServiceInfo] = []
        for (name, port, metricsPath, schemaPath) in targets {
            let url = URL(string: "http://\(host):\(port)\(metricsPath)")!
            let reachable = await ping(url)
            services.append(.init(name: name, port: port, metrics_url: "http://\(host):\(port)\(metricsPath)", schema_url: "http://\(host):\(port)\(schemaPath)", reachable: reachable))
        }
        let status = Components.Schemas.FKStatus(services: services)
        return .ok(.init(body: .json(status)))
    }

    public func fkBuild(_ input: Operations.fkBuild.Input) async throws -> Operations.fkBuild.Output {
        let res = run("/usr/bin/env", ["swift", "build"], cwd: FileManager.default.currentDirectoryPath, timeout: 300)
        return .ok(.init(body: .json(ack(res.ok, res.err.isEmpty ? "built" : res.err))))
    }

    public func fkUp(_ input: Operations.fkUp.Input) async throws -> Operations.fkUp.Output {
        let root = FileManager.default.currentDirectoryPath
        let script = URL(fileURLWithPath: root).appendingPathComponent("Scripts/dev-up").path
        let res = run("/bin/bash", [script], cwd: root, timeout: 120)
        return .ok(.init(body: .json(ack(res.ok, res.err.isEmpty ? "up" : res.err))))
    }

    public func fkDown(_ input: Operations.fkDown.Input) async throws -> Operations.fkDown.Output {
        let root = FileManager.default.currentDirectoryPath
        let script = URL(fileURLWithPath: root).appendingPathComponent("Scripts/dev-down").path
        let res = run("/bin/bash", [script, "--force"], cwd: root, timeout: 60)
        return .ok(.init(body: .json(ack(res.ok, res.err.isEmpty ? "down" : res.err))))
    }

    public func fkLogs(_ input: Operations.fkLogs.Input) async throws -> Operations.fkLogs.Output {
        let svc = input.query.service
        let lines = input.query.lines ?? 200
        var text = ""
        if svc == "tool-server" {
            let root = FileManager.default.currentDirectoryPath
            let logPath = URL(fileURLWithPath: root).appendingPathComponent(".build/tool-server.log").path
            if let data = try? Data(contentsOf: URL(fileURLWithPath: logPath)), let s = String(data: data, encoding: .utf8) {
                let parts = s.split(separator: "\n")
                text = parts.suffix(lines).joined(separator: "\n")
            }
        } else {
            // docker compose logs for the named service
            let res = run("/usr/bin/env", ["docker", "compose", "-f", "Configuration/tool-server/docker-compose.yml", "logs", "--no-color", "--tail", String(lines), svc], cwd: FileManager.default.currentDirectoryPath, timeout: 30)
            text = res.out.isEmpty ? res.err : res.out
        }
        return .ok(.init(body: .plainText(HTTPBody(text))))
    }
}

