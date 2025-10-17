import Foundation

public enum EnvironmentOverallState: Equatable, Sendable {
    case unavailable(String)
    case idle
    case checking
    case starting
    case stopping
    case running
    case failed(String)
}

public enum EnvironmentServiceState: String, Equatable, Sendable {
    case up
    case down
    case unknown
}

public struct EnvironmentServiceStatus: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let port: Int
    public let state: EnvironmentServiceState
    public let pid: String?

    public init(name: String, port: Int, state: EnvironmentServiceState, pid: String?) {
        self.id = name
        self.name = name
        self.port = port
        self.state = state
        self.pid = pid
    }
}

public struct EnvironmentLogEntry: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let line: String

    public init(timestamp: Date = Date(), line: String) {
        self.timestamp = timestamp
        self.line = line
    }
}

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
            let output = try await runAndCapture(script: script, arguments: [])
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
            if includeExtras {
                arguments.append("--all")
            }
            if force {
                arguments.append("--force")
            }
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

    // MARK: - Helpers

    private func runAndCapture(script: URL, arguments: [String]) async throws -> String {
        try await Task.detached(priority: .utility) { () -> String in
            let process = Process()
            process.executableURL = script
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment
            if let repoRoot = self.repoRoot {
                process.currentDirectoryURL = repoRoot
            }

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
            } catch {
                throw EnvironmentError.runFailed(script.lastPathComponent, error.localizedDescription)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let status = process.terminationStatus

            guard status == 0 else {
                throw EnvironmentError.processFailed(script.lastPathComponent, status)
            }
            return String(decoding: data, as: UTF8.self)
        }.value
    }

    private func runStreaming(script: URL, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = script
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment
            if let repoRoot = self.repoRoot {
                process.currentDirectoryURL = repoRoot
            }

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self else { return }
                let data = handle.availableData
                if data.isEmpty { return }
                if let text = String(data: data, encoding: .utf8) {
                    Task { @MainActor in
                        self.consumeLogFragment(text)
                    }
                }
            }

            process.terminationHandler = { [weak self] proc in
                guard let self else { return }
                pipe.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor in
                    self.finishLogStream()
                    self.runningProcess = nil
                    if proc.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: EnvironmentError.processFailed(script.lastPathComponent, proc.terminationStatus))
                    }
                }
            }

            do {
                try process.run()
                self.runningProcess = process
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: EnvironmentError.runFailed(script.lastPathComponent, error.localizedDescription))
            }
        }
    }

    private func consumeLogFragment(_ fragment: String) {
        let combined = logRemainder + fragment
        let lines = combined.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines.dropLast() {
            appendLogLine(String(line))
        }
        if let remainder = lines.last, !combined.hasSuffix("\n") {
            logRemainder = String(remainder)
        } else {
            logRemainder = ""
        }
    }

    private func finishLogStream() {
        if !logRemainder.isEmpty {
            appendLogLine(logRemainder)
            logRemainder = ""
        }
    }

    private func appendLogLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        logs.append(EnvironmentLogEntry(line: trimmed))
        if logs.count > logLimit {
            logs.removeFirst(logs.count - logLimit)
        }
    }

    private func applyStatusOutput(_ output: String) {
        let rows = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard rows.count > 1 else {
            services = []
            overallState = .idle
            return
        }

        var parsed: [EnvironmentServiceStatus] = []
        for row in rows.dropFirst() {
            let parts = row.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 3 else { continue }
            let name = parts[0]
            let port = Int(parts[1]) ?? 0
            let state = EnvironmentServiceState(rawValue: parts[2]) ?? .unknown
            let pid = parts.count > 3 ? parts[3] : nil
            parsed.append(EnvironmentServiceStatus(name: name, port: port, state: state, pid: pid?.isEmpty == true ? nil : pid))
        }
        services = parsed
        lastStatusCheck = Date()

        let core = parsed.filter { coreServices.contains($0.name) }
        let shouldHoldBusyState: Bool = {
            switch overallState {
            case .starting, .stopping:
                return true
            default:
                return false
            }
        }()

        if !core.isEmpty, core.allSatisfy({ $0.state == .up }) {
            overallState = .running
        } else if shouldHoldBusyState {
            // keep current busy state (start/stop in progress)
        } else {
            overallState = .idle
        }
    }
}
