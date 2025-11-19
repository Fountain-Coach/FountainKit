import XCTest
@testable import instrument_lint

final class InstrumentLintTests: XCTestCase {
    func testCheckInstrumentPassesWhenStructureIsValid() async throws {
        let fm = FileManager.default
        let tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("instrument-lint-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmpRoot, withIntermediateDirectories: true)

        // Spec file
        let specDir = tmpRoot
            .appendingPathComponent("Packages/FountainSpecCuration/openapi/v1", isDirectory: true)
        try fm.createDirectory(at: specDir, withIntermediateDirectories: true)
        let specURL = specDir.appendingPathComponent("test-instrument.yml", isDirectory: false)
        try "openapi: 3.1.0\ninfo:\n  title: Test\n  version: 1.0.0\npaths: {}\n".data(using: .utf8)?.write(to: specURL)

        // Scripts/openapi/openapi-to-facts.sh containing the agentId
        let scriptsDir = tmpRoot.appendingPathComponent("Scripts/openapi", isDirectory: true)
        try fm.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        let scriptURL = scriptsDir.appendingPathComponent("openapi-to-facts.sh", isDirectory: false)
        try "#!/usr/bin/env bash\n# uses fountain.coach/agent/test-instrument/service\n".data(using: .utf8)?.write(to: scriptURL)

        // Test module path with a Swift file containing required symbol
        let testsDir = tmpRoot
            .appendingPathComponent("Packages/FountainApps/Tests/TestInstrumentTests", isDirectory: true)
        try fm.createDirectory(at: testsDir, withIntermediateDirectories: true)
        let testFile = testsDir.appendingPathComponent("TestInstrumentSurfaceTests.swift", isDirectory: false)
        try "final class TestInstrumentSurfaceTests {}\n".data(using: .utf8)?.write(to: testFile)

        let inst = InstrumentLint.Instrument(
            appId: "test-instrument",
            agentId: "fountain.coach/agent/test-instrument/service",
            corpusId: "test-instrument",
            spec: "test-instrument.yml",
            runtimeAgentId: nil,
            testModulePath: "Packages/FountainApps/Tests/TestInstrumentTests",
            snapshotBaselinesDir: nil,
            requiredTestSymbols: ["TestInstrumentSurfaceTests"]
        )

        let ok = await InstrumentLint.checkInstrument(inst, root: tmpRoot)
        XCTAssertTrue(ok, "valid instrument structure should pass checkInstrument")
    }

    func testCheckInstrumentFailsWhenSpecIsMissing() async throws {
        let fm = FileManager.default
        let tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("instrument-lint-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmpRoot, withIntermediateDirectories: true)

        let inst = InstrumentLint.Instrument(
            appId: "missing-spec",
            agentId: "fountain.coach/agent/missing-spec/service",
            corpusId: "missing-spec",
            spec: "missing.yml",
            runtimeAgentId: nil,
            testModulePath: nil,
            snapshotBaselinesDir: nil,
            requiredTestSymbols: nil
        )

        let ok = await InstrumentLint.checkInstrument(inst, root: tmpRoot)
        XCTAssertFalse(ok, "missing spec should cause checkInstrument to fail")
    }
}

