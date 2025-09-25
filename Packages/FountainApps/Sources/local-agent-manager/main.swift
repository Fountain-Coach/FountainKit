import Foundation
import FountainStoreClient

struct LocalAgentConfig: Codable {
    var repo_url: String
    var rel_dir: String
    var backend: String
    var host: String
    var port: Int

    static let `default` = LocalAgentConfig(
        repo_url: "https://github.com/Fountain-Coach/LocalAgent",
        rel_dir: "External/LocalAgent",
        backend: "mock",
        host: "127.0.0.1",
        port: 8080
    )
}

@main
struct LocalAgentManager {
    static func main() async {
        var args = CommandLine.arguments.dropFirst()
        guard let command = args.first else {
            eprint("usage: local-agent-manager <ensure|start|stop|status|precompile|health> [--repo-root PATH]")
            exit(2)
        }
        args = args.dropFirst()
        let repoRoot = parseOption(name: "--repo-root", in: &args) ?? FileManager.default.currentDirectoryPath
        do {
            let config = try await loadConfig(repoRoot: repoRoot)
            switch command {
            case "ensure":
                try ensureRepo(config: config, repoRoot: repoRoot)
            case "start":
                try ensureRepo(config: config, repoRoot: repoRoot)
                try configureAgent(config: config, repoRoot: repoRoot)
                try await start(config: config, repoRoot: repoRoot)
            case "stop":
                try stop(repoRoot: repoRoot)
            case "status":
                let ok = await health(config: config)
                print(ok ? "healthy" : "unhealthy")
                exit(ok ? 0 : 1)
            case "precompile":
                try ensureRepo(config: config, repoRoot: repoRoot)
                try precompile(repoRoot: repoRoot)
            case "health":
                let ok = await health(config: config)
                print(ok ? "ok" : "fail")
                exit(ok ? 0 : 1)
            default:
                eprint("unknown command: \(command)")
                exit(2)
            }
        } catch {
            eprint("local-agent-manager error: \(error)")
            exit(1)
        }
    }

    // MARK: - Config
    static func loadConfig(repoRoot: String) async throws -> LocalAgentConfig {
        if let store = ConfigurationStore.fromEnvironment(),
           let data = store.getSync("local-agent/config.json") {
            if let cfg = try? JSONDecoder().decode(LocalAgentConfig.self, from: data) {
                return cfg
            }
        }
        // Fallback to file under Configuration/
        let fileURL = URL(fileURLWithPath: repoRoot).appendingPathComponent("Configuration/local-agent.json")
        if let data = try? Data(contentsOf: fileURL), let cfg = try? JSONDecoder().decode(LocalAgentConfig.self, from: data) {
            return cfg
        }
        return .default
    }

    // MARK: - Repo
    static func ensureRepo(config: LocalAgentConfig, repoRoot: String) throws {
        let rel = config.rel_dir
        let dirURL = URL(fileURLWithPath: repoRoot, isDirectory: true).appendingPathComponent(rel, isDirectory: true)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue {
            return
        }
        try FileManager.default.createDirectory(at: dirURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try run("git", ["clone", "--depth=1", config.repo_url, dirURL.path])
    }

    // MARK: - Configure
    static func configureAgent(config: LocalAgentConfig, repoRoot: String) throws {
        let agentRoot = URL(fileURLWithPath: repoRoot).appendingPathComponent(config.rel_dir).appendingPathComponent("AgentService")
        let example = agentRoot.appendingPathComponent("agent-config.json.example")
        let configFile = agentRoot.appendingPathComponent("agent-config.json")
        if !FileManager.default.fileExists(atPath: configFile.path) {
            if FileManager.default.fileExists(atPath: example.path) {
                try FileManager.default.copyItem(at: example, to: configFile)
            } else {
                // create minimal config
                let obj: [String: Any] = [
                    "host": config.host,
                    "port": config.port,
                    "backend": config.backend
                ]
                let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])
                try data.write(to: configFile)
                return
            }
        }
        // Patch existing config: set backend/host/port if keys exist or append
        let data = try Data(contentsOf: configFile)
        if var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            obj["backend"] = config.backend
            obj["host"] = config.host
            obj["port"] = config.port
            let out = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])
            try out.write(to: configFile)
        }
    }

    // MARK: - Start/Stop
    static func start(config: LocalAgentConfig, repoRoot: String) async throws {
        let pidFile = pidURL(repoRoot: repoRoot)
        if let pid = try? String(contentsOf: pidFile), let p = Int32(pid.trimmingCharacters(in: .whitespacesAndNewlines)), kill(p, 0) == 0 {
            print("already running pid \(p)")
            return
        }
        let dir = URL(fileURLWithPath: repoRoot).appendingPathComponent(config.rel_dir)
        let logDir = URL(fileURLWithPath: repoRoot).appendingPathComponent(".fountain/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let logURL = logDir.appendingPathComponent("local-agent.log")
        let task = Process()
        task.currentDirectoryURL = dir
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["swift", "run", "--package-path", "AgentService", "AgentService"]
        let fh = try FileHandle(forWritingTo: logURL)
        task.standardOutput = fh
        task.standardError = fh
        try task.run()
        let pidStr = String(task.processIdentifier)
        try FileManager.default.createDirectory(at: pidFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try pidStr.data(using: .utf8)?.write(to: pidFile)
        // wait until health ok or timeout
        for _ in 0..<60 {
            if await health(config: config) { print("healthy"); return }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        eprint("failed to become healthy")
    }

    static func stop(repoRoot: String) throws {
        let pidFile = pidURL(repoRoot: repoRoot)
        guard let pid = try? String(contentsOf: pidFile), let p = Int32(pid.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            print("not running")
            return
        }
        kill(p, SIGTERM)
        try? FileManager.default.removeItem(at: pidFile)
    }

    // MARK: - Precompile
    static func precompile(repoRoot: String) throws {
        let dir = URL(fileURLWithPath: repoRoot).appendingPathComponent(LocalAgentConfig.default.rel_dir)
        try run("swift", ["build", "--package-path", "AgentService", "-c", "release"], cwd: dir)
    }

    // MARK: - Health
    static func health(config: LocalAgentConfig) async -> Bool {
        guard let url = URL(string: "http://\(config.host):\(config.port)/health") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse { return (200...299).contains(http.statusCode) }
        } catch {}
        return false
    }

    // MARK: - Utils
    static func run(_ tool: String, _ args: [String], cwd: URL? = nil) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [tool] + args
        p.currentDirectoryURL = cwd
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            throw NSError(domain: "local-agent-manager", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "command failed: \(tool) \(args.joined(separator: " "))"])
        }
    }

    static func pidURL(repoRoot: String) -> URL {
        URL(fileURLWithPath: repoRoot).appendingPathComponent(".fountain/pids/local-agent.pid")
    }

    static func parseOption(name: String, in args: inout ArraySlice<String>) -> String? {
        if let idx = args.firstIndex(of: name) {
            let valIdx = args.index(after: idx)
            guard valIdx < args.endIndex else { return nil }
            let val = args[valIdx]
            args.removeSubrange(idx...valIdx)
            return val
        }
        return nil
    }
}

// MARK: - Stderr helper
let stderr = FileHandle.standardError
func eprint(_ items: Any..., to handle: FileHandle = stderr) {
    let text = items.map { String(describing: $0) }.joined(separator: " ") + "\n"
    handle.write(Data(text.utf8))
}
