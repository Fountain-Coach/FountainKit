import Foundation
import FountainAIKit

@MainActor
public final class FountainEnvironmentManager: ObservableObject {
    public enum EnvironmentError: Error, CustomStringConvertible {
        case scriptMissing(String)
        case processFailed(String, Int32)
        case runFailed(String, String)

        public var description: String {
            switch self {
            case .scriptMissing(let name):
                return "Environment script missing: \(name)"
            case .processFailed(let name, let code):
                return "\(name) exited with status \(code)"
            case .runFailed(let name, let details):
                return "Failed to run \(name): \(details)"
            }
        }
    }

    @Published public private(set) var overallState: EnvironmentOverallState = .unavailable("FountainKit root not configured")
    @Published public private(set) var services: [EnvironmentServiceStatus] = []
    @Published public private(set) var logs: [EnvironmentLogEntry] = []
    @Published public private(set) var lastStatusCheck: Date? = nil

    public var isConfigured: Bool { scriptsRoot != nil }
    public var isBusy: Bool {
        switch overallState {
        case .starting, .checking, .stopping:
            return true
        default:
            return false
        }
    }

    private let scriptsRoot: URL?
    private let repoRoot: URL?
    private var runningProcess: Process?
    private var logRemainder: String = ""
    private let logLimit = 400
    private let coreServices: Set<String> = [
        "baseline-awareness",
        "bootstrap",
        "planner",
        "function-caller",
        "persist",
        "gateway"
    ]

    public init(fountainRepoRoot: URL?) {
        if let root = fountainRepoRoot {
            let scripts = root.appendingPathComponent("Scripts", isDirectory: true)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: scripts.path, isDirectory: &isDir), isDir.boolValue {
                self.scriptsRoot = scripts
                self.repoRoot = root
                self.overallState = .idle
            } else {
                self.scriptsRoot = nil
                self.repoRoot = nil
                self.overallState = .unavailable("Scripts directory missing at \(scripts.path)")
            }
        } else {
            self.scriptsRoot = nil
            self.repoRoot = nil
            self.overallState = .unavailable("FountainKit root not configured")
        }
    }

    // MARK: - Public control

    public func refreshStatus() async {
        guard let scriptsRoot else {
            return
        }
        guard runningProcess == nil else {
            // A streaming process is active; delay status refresh
            return
        }
        let script = scriptsRoot.appendingPathComponent("dev-status")
        if !FileManager.default.isExecutableFile(atPath: script.path) {
            overallState = .unavailable("Scripts/dev-status is not executable")
            return
        }
        overallState = .checking
        do {
            let output = try await runCapturing(script: script)
            applyStatusOutput(output)
        } catch {
            overallState = .failed(error.localizedDescription)
        }
    }

    public func startEnvironment(includeExtras: Bool) async {
        guard let scriptsRoot else {
            return
        }
        guard runningProcess == nil else {
            return
        }
        let script = scriptsRoot.appendingPathComponent("dev-up")
        if !FileManager.default.isExecutableFile(atPath: script.path) {
            overallState = .unavailable("Scripts/dev-up is not executable")
            return
        }

        overallState = .starting
        clearLogs()
        do {
            var arguments: [String] = ["--check"]
            if includeExtras {
                arguments.insert("--all", at: 0)
            }
            try await runStreaming(script: script, arguments: arguments)
            // dev-up succeeded; probe final status
            await refreshStatus()
            if case .running = overallState {
                // ok
            } else {
                overallState = .running
            }
        } catch {
            // Some dev-up implementations return non-zero when services already up.
            // Probe status; if core services are up, treat as success.
            await refreshStatus()
            if case .running = overallState {
                return
            }
            overallState = .failed(error.localizedDescription)
        }
    }

    public func stopEnvironment(includeExtras: Bool, force: Bool) async {
        guard let scriptsRoot else {
            return
        }
        guard runningProcess == nil else {
            return
        }
        let script = scriptsRoot.appendingPathComponent("dev-down")
        if !FileManager.default.isExecutableFile(atPath: script.path) {
            overallState = .unavailable("Scripts/dev-down is not executable")
            return
        }

        overallState = .stopping
        do {
            var arguments: [String] = []
            if includeExtras { arguments.append("--all") }
            if force { arguments.append("--force") }
            try await runStreaming(script: script, arguments: arguments)
            overallState = .idle
            await refreshStatus()
        } catch {
            overallState = .failed(error.localizedDescription)
        }
    }

    public func clearLogs() {
        logs.removeAll()
        logRemainder = ""
    }

    // MARK: - Process controls

    public func forceKillPID(_ pid: String) async {
        await Task(priority: .utility) {
            func run(_ args: [String]) throws {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/kill")
                proc.arguments = args
                try proc.run(); proc.waitUntilExit()
            }
            do {
                try run(["-TERM", pid])
                // brief grace period
                try await Task.sleep(nanoseconds: 200_000_000)
                try run(["-0", pid]) // probe if still alive
                // still alive -> KILL
                try run(["-KILL", pid])
            } catch {
                // Best-effort: ignore failures, status refresh will reflect reality
            }
        }.value
        await refreshStatus()
    }

    public func restartService(_ service: EnvironmentServiceStatus) async {
        if let pid = service.pid { await forceKillPID(pid) }
        guard let scriptsRoot, runningProcess == nil else {
            await refreshStatus()
            return
        }
        let script = scriptsRoot.appendingPathComponent("dev-up")
        do { try await runStreaming(script: script, arguments: ["--check"]) } catch { }
        await refreshStatus()
    }

    public func fixAll() async {
        let targets = services.filter { $0.state != .up }
        for svc in targets { if let pid = svc.pid { await forceKillPID(pid) } }
        guard let scriptsRoot, runningProcess == nil else {
            await refreshStatus(); return
        }
        let script = scriptsRoot.appendingPathComponent("dev-up")
        do { try await runStreaming(script: script, arguments: ["--check"]) } catch { }
        await refreshStatus()
    }

    // MARK: - Private helpers

    private func runCapturing(script: URL, arguments: [String] = []) async throws -> String {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = script
        proc.arguments = arguments
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run(); proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if proc.terminationStatus == 0 { return String(data: data, encoding: .utf8) ?? "" }
        throw EnvironmentError.processFailed(script.lastPathComponent, proc.terminationStatus)
    }

    private func runStreaming(script: URL, arguments: [String]) async throws {
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = script
        proc.arguments = arguments
        proc.standardOutput = pipe
        proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let str = String(data: handle.availableData, encoding: .utf8), !str.isEmpty else { return }
            Task { @MainActor in self?.appendLog(str) }
        }
        try proc.run(); runningProcess = proc
        defer { runningProcess = nil; pipe.fileHandleForReading.readabilityHandler = nil }
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            throw EnvironmentError.processFailed(script.lastPathComponent, proc.terminationStatus)
        }
    }

    private func appendLog(_ chunk: String) {
        var leftover = logRemainder + chunk
        while let range = leftover.range(of: "\n") {
            let line = String(leftover[..<range.lowerBound])
            logs.append(EnvironmentLogEntry(line: line))
            if logs.count > logLimit { logs.removeFirst(logs.count - logLimit) }
            leftover = String(leftover[range.upperBound...])
        }
        logRemainder = leftover
    }

    private func applyStatusOutput(_ text: String) {
        lastStatusCheck = Date()
        // Extremely simple status parse: a line per service "name:port:state:pid?"
        var running: [EnvironmentServiceStatus] = []
        var all: [EnvironmentServiceStatus] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: ":")
            guard parts.count >= 3 else { continue }
            let name = String(parts[0])
            let port = Int(parts[1]) ?? 0
            let state = EnvironmentServiceState(rawValue: String(parts[2])) ?? .unknown
            let pid = parts.count >= 4 ? String(parts[3]) : nil
            let item = EnvironmentServiceStatus(name: name, port: port, state: state, pid: pid)
            all.append(item)
            if state == .up { running.append(item) }
        }
        services = all
        // Heuristic for overall state
        let runningNames = Set(running.map { $0.name })
        if coreServices.isSubset(of: runningNames) {
            overallState = .running
        } else if running.isEmpty {
            overallState = .idle
        } else {
            overallState = .checking
        }
    }
}
