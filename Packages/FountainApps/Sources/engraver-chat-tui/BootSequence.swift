import Foundation
import EngraverChatCore

struct BootUpdate: Sendable {
    let newLines: [String]
    let completed: Bool
    let exitCode: Int32?
}

actor BootSequence {
    private var lines: [String] = []
    private var nextIndex: Int = 0
    private var completed: Bool = false
    private var exitCode: Int32?

    private init() {}

    static func start(scriptURL: URL?, environment: [String: String]) async -> BootSequence {
        let sequence = BootSequence()
        await sequence.bootstrap(scriptURL: scriptURL, environment: environment)
        return sequence
    }

    private func bootstrap(scriptURL: URL?, environment: [String: String]) async {
        guard let scriptURL else {
            lines.append("[boot] Scripts/dev-up not found; skipping boot.")
            completed = true
            return
        }

        lines.append("[boot] Launching dev-up --check…")

        Task.detached {
            var env = environment
            if env["GATEWAY_BEARER"].flatMap({ !$0.isEmpty }) != true,
               let bearer = await MainActor.run { SecretStoreHelper.read(service: "FountainAI", account: "GATEWAY_BEARER") } {
                env["GATEWAY_BEARER"] = bearer
            }
            if env["OPENAI_API_KEY"].flatMap({ !$0.isEmpty }) != true,
               let apiKey = await MainActor.run { SecretStoreHelper.read(service: "FountainAI", account: "OPENAI_API_KEY") } {
                env["OPENAI_API_KEY"] = apiKey
            }
            await self.runProcess(scriptURL: scriptURL, environment: env)
        }
    }

    private func runProcess(scriptURL: URL, environment: [String: String]) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path, "--check"]
        process.environment = environment
        process.currentDirectoryURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            appendLine("Failed to launch dev-up: \(error)")
            finish(code: nil)
            return
        }

        let reader = pipe.fileHandleForReading

        Task.detached { [weak process] in
            do {
                for try await line in reader.bytes.lines {
                    await self.appendLine(line)
                }
            } catch {
                await self.appendLine("Error reading dev-up output: \(error)")
            }
            if let process {
                process.waitUntilExit()
                await self.finish(code: process.terminationStatus)
            } else {
                await self.finish(code: nil)
            }
        }
    }

    private func appendLine(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lines.append("[boot] \(trimmed)")
    }

    private func finish(code: Int32?) {
        guard !completed else { return }
        completed = true
        exitCode = code
        if let code {
            if code == 0 {
                lines.append("[boot] dev-up completed successfully.")
            } else {
                lines.append("[boot] dev-up exited with code \(code).")
            }
        } else {
            lines.append("[boot] dev-up finished.")
        }
    }

    func poll() -> BootUpdate {
        let slice = nextIndex < lines.count ? Array(lines[nextIndex...]) : []
        nextIndex = lines.count
        return BootUpdate(newLines: slice, completed: completed, exitCode: exitCode)
    }
}
