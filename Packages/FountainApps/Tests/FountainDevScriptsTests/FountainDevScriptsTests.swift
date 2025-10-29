// Robot-only mode: exclude this suite when building robot tests
#if !ROBOT_ONLY

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

final class FountainDevScriptsTests: XCTestCase {
    private var repoRoot: URL { URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // …/Tests/FountainDevScriptsTests
            .deletingLastPathComponent() // …/Tests
            .deletingLastPathComponent() // …/FountainApps
            .deletingLastPathComponent() // …/Packages
            .deletingLastPathComponent() // …/FountainKit (repo root)
    }

    private var scriptsDir: URL { repoRoot.appendingPathComponent("Scripts", isDirectory: true) }
    private var pidsDir: URL { repoRoot.appendingPathComponent(".fountain/pids", isDirectory: true) }

    override func tearDown() async throws {
        _ = try? run(["bash", scriptsDir.appendingPathComponent("dev-down").path])
    }

    func testDevUpStartsGatewayAndDevDownStopsIt() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["FOUNTAIN_INTEGRATION"] == "1" else {
            throw XCTSkip("Set FOUNTAIN_INTEGRATION=1 to run dev scripts integration test.")
        }
        // Ensure clean state
        _ = try? run(["bash", scriptsDir.appendingPathComponent("dev-down").path])

        // Start core services
        let upResult = try run(["bash", scriptsDir.appendingPathComponent("dev-up").path], env: [
            "DEV_UP_USE_BIN": "1",
            "DEV_UP_NO_START_LOCAL_AGENT": "1"
        ])
        if upResult.exitCode != 0 {
            XCTFail("dev-up failed: exit=\(upResult.exitCode) stderr=\(upResult.stderr) stdout=\(upResult.stdout)")
        }

        // Expect gateway pid file and a listening metrics endpoint
        try await eventually(timeout: 30.0, interval: 0.5) {
            let pidURL = self.pidsDir.appendingPathComponent("gateway.pid")
            var isDir: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: pidURL.path, isDirectory: &isDir), "gateway pid file should exist")
            XCTAssertFalse(isDir.boolValue)

            let status = await self.httpStatus("http://127.0.0.1:8010/metrics")
            XCTAssertEqual(status, 200)
        }

        // Stop everything
        let downResult = try run(["bash", scriptsDir.appendingPathComponent("dev-down").path])
        if downResult.exitCode != 0 {
            XCTFail("dev-down failed: exit=\(downResult.exitCode) stderr=\(downResult.stderr) stdout=\(downResult.stdout)")
        }

        // After stop, metrics should be unreachable and pid removed (eventually)
        try await eventually(timeout: 10.0, interval: 0.5) {
            let pidURL = self.pidsDir.appendingPathComponent("gateway.pid")
            XCTAssertFalse(FileManager.default.fileExists(atPath: pidURL.path))

            let status = await self.httpStatus("http://127.0.0.1:8010/metrics")
            XCTAssertNil(status, "gateway should be down after dev-down")
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func run(_ cmd: [String], env extra: [String: String] = [:]) throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = cmd
        var environment = ProcessInfo.processInfo.environment
        for (k, v) in extra { environment[k] = v }
        p.environment = environment
        let out = Pipe(); let err = Pipe()
        p.standardOutput = out; p.standardError = err
        try p.run(); p.waitUntilExit()
        let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (p.terminationStatus, o, e)
    }

    private func httpStatus(_ url: String) async -> Int? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u)
        req.timeoutInterval = 1.5
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode
        } catch {
            return nil
        }
    }

    private func eventually(timeout: TimeInterval, interval: TimeInterval, _ block: @escaping () async throws -> Void) async throws {
        let start = Date()
        var lastError: Error?
        repeat {
            do { try await block(); return } catch { lastError = error }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        } while Date().timeIntervalSince(start) < timeout
        if let lastError { throw lastError }
    }
}

#endif // !ROBOT_ONLY
