import Foundation

struct DockerComposeManager {
    let composeFile: String
    let workdir: String

    init(composeFile: String? = nil, workdir: String? = nil) {
        self.composeFile = composeFile ?? ProcessInfo.processInfo.environment["TOOLSERVER_COMPOSE_FILE"] ?? "Configuration/tool-server/docker-compose.yml"
        self.workdir = workdir ?? ProcessInfo.processInfo.environment["TOOLSERVER_WORKDIR"] ?? FileManager.default.currentDirectoryPath
    }

    /// Runs a tool via `docker compose run --rm` for the given service with provided args.
    @discardableResult
    func run(service: String, args: [String]) throws -> (code: Int32, stdout: Data, stderr: Data) {
        var env = ProcessInfo.processInfo.environment
        env["TOOLSERVER_WORKDIR"] = workdir
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["docker", "compose", "-f", composeFile, "run", "--rm", "-T", service] + args
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.environment = env
        try proc.run()
        proc.waitUntilExit()
        let stdout = outPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = errPipe.fileHandleForReading.readDataToEndOfFile()
        return (proc.terminationStatus, stdout, stderr)
    }
}

