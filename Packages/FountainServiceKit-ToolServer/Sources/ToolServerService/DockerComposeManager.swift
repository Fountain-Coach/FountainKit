import Foundation

struct DockerComposeManager {
    let composeFile: String
    let workdir: String
    let projectName: String
    let timeoutSec: Int
    let dockerBinary: String

    init(
        composeFile: String? = nil,
        workdir: String? = nil,
        projectName: String? = nil,
        timeoutSec: Int? = nil,
        dockerBinary: String? = nil
    ) {
        let env = ProcessInfo.processInfo.environment
        self.composeFile = composeFile ?? env["TOOLSERVER_COMPOSE_FILE"] ?? "Configuration/tool-server/docker-compose.yml"
        self.workdir = workdir ?? env["TOOLSERVER_WORKDIR"] ?? FileManager.default.currentDirectoryPath
        self.projectName = projectName ?? env["TOOLSERVER_COMPOSE_PROJECT_NAME"] ?? "toolserver"
        self.timeoutSec = timeoutSec ?? Int(env["TOOLSERVER_TIMEOUT"] ?? "120") ?? 120
        self.dockerBinary = dockerBinary ?? env["DOCKER_BINARY"] ?? "docker"
    }

    private func makeProcess(args: [String], extraEnv: [String: String] = [:]) -> (Process, Pipe, Pipe) {
        var env = ProcessInfo.processInfo.environment
        env["TOOLSERVER_WORKDIR"] = workdir
        env["COMPOSE_PROJECT_NAME"] = projectName
        for (k, v) in extraEnv { env[k] = v }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [dockerBinary] + args
        proc.currentDirectoryURL = URL(fileURLWithPath: workdir)
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        proc.environment = env
        return (proc, out, err)
    }

    private func runWithTimeout(proc: Process, out: Pipe, err: Pipe) throws -> (Int32, Data, Data) {
        let group = DispatchGroup()
        group.enter()
        proc.terminationHandler = { _ in group.leave() }
        try proc.run()
        let waitResult = group.wait(timeout: .now() + .seconds(timeoutSec))
        if waitResult == .timedOut {
            // Kill the process and collect what we have.
            proc.terminate()
            _ = group.wait(timeout: .now() + .seconds(5))
            let stdout = out.fileHandleForReading.readDataToEndOfFile()
            let stderr = err.fileHandleForReading.readDataToEndOfFile()
            return (SIGKILL, stdout, stderr)
        }
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        return (proc.terminationStatus, stdout, stderr)
    }

    func available() -> Bool {
        let (proc, out, err) = makeProcess(args: ["--version"])
        do {
            let (code, _, _) = try runWithTimeout(proc: proc, out: out, err: err)
            return code == 0
        } catch { return false }
    }

    @discardableResult
    func pull(services: [String] = []) throws -> (code: Int32, stdout: Data, stderr: Data) {
        let args = ["compose", "-f", composeFile, "pull"] + services
        let (proc, out, err) = makeProcess(args: args)
        let (code, o, e) = try runWithTimeout(proc: proc, out: out, err: err)
        return (code, o, e)
    }

    @discardableResult
    func up(services: [String] = [], detach: Bool = true) throws -> (code: Int32, stdout: Data, stderr: Data) {
        var args = ["compose", "-f", composeFile, "up"]
        if detach { args.append("-d") }
        args += services
        let (proc, out, err) = makeProcess(args: args)
        return try runWithTimeout(proc: proc, out: out, err: err)
    }

    @discardableResult
    func down() throws -> (code: Int32, stdout: Data, stderr: Data) {
        let (proc, out, err) = makeProcess(args: ["compose", "-f", composeFile, "down"])
        return try runWithTimeout(proc: proc, out: out, err: err)
    }

    @discardableResult
    func ps() throws -> (code: Int32, stdout: Data, stderr: Data) {
        let (proc, out, err) = makeProcess(args: ["compose", "-f", composeFile, "ps"])
        return try runWithTimeout(proc: proc, out: out, err: err)
    }

    /// Runs a tool via `docker compose run --rm` for the given service with provided args.
    @discardableResult
    func run(service: String, args: [String], extraEnv: [String: String] = [:]) throws -> (code: Int32, stdout: Data, stderr: Data) {
        let base = ["compose", "-f", composeFile, "run", "--rm", "-T", service]
        let (proc, out, err) = makeProcess(args: base + args, extraEnv: extraEnv)
        return try runWithTimeout(proc: proc, out: out, err: err)
    }
}
