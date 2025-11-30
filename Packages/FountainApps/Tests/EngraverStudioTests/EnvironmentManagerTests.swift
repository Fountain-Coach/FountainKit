#if !ROBOT_ONLY
import XCTest
@testable import EngraverChatCore
@testable import FountainDevHarness
import Foundation

final class EnvironmentManagerTests: XCTestCase {
    func testRefreshStatusParsesOutput() async throws {
        let root = try makeFakeEnvironmentScripts()
        let manager = await MainActor.run { FountainEnvironmentManager(fountainRepoRoot: root) }

        await manager.refreshStatus()

        await MainActor.run {
            XCTAssertEqual(manager.services.count, 9)
            XCTAssertEqual(manager.services.filter { $0.state == .up }.count, 6)
            XCTAssertEqual(manager.overallState, .running)
        }
    }

    func testStartEnvironmentAppendsLogs() async throws {
        let root = try makeFakeEnvironmentScripts()
        let manager = await MainActor.run { FountainEnvironmentManager(fountainRepoRoot: root) }

        await manager.refreshStatus()
        try await wait(for: { await MainActor.run { manager.overallState == .running } })

        let logsEmpty = await MainActor.run { manager.logs.isEmpty }
        XCTAssertTrue(logsEmpty)

        await manager.startEnvironment(includeExtras: false)
        try await wait(for: { await MainActor.run { manager.overallState == .running } })

        let logs = await MainActor.run { manager.logs }
        XCTAssertFalse(logs.isEmpty)
        XCTAssertTrue(logs.contains(where: { $0.line.contains("ready") }))
    }

    // MARK: - Helpers

    private func makeFakeEnvironmentScripts() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let scripts = root.appendingPathComponent("Scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)

        let statusScript = """
        #!/bin/bash
        cat <<'EOF'
        baseline-awareness:8001:up:111
        bootstrap:8002:up:112
        planner:8003:up:113
        function-caller:8004:up:114
        persist:8005:up:115
        gateway:8010:up:116
        semantic-browser:8007:down:
        tools-factory:8011:down:
        tool-server:8012:down:
        EOF
        """

        let upScript = """
        #!/bin/bash
        echo "[dev-up] Starting core services"
        sleep 0.05
        echo "[dev-up] baseline-awareness ready"
        echo "[dev-up] done"
        """

        let downScript = """
        #!/bin/bash
        echo "[dev-down] Stopping services"
        exit 0
        """

        try writeExecutable(script: scripts.appendingPathComponent("dev-status"), contents: statusScript)
        try writeExecutable(script: scripts.appendingPathComponent("dev-up"), contents: upScript)
        try writeExecutable(script: scripts.appendingPathComponent("dev-down"), contents: downScript)

        return root
    }

    private func writeExecutable(script: URL, contents: String) throws {
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: script.path)
    }

    private func wait(for predicate: @escaping () async -> Bool, timeout: TimeInterval = 2.0) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }
}

#endif // !ROBOT_ONLY
