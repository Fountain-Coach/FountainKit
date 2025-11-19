import XCTest
@testable import InstrumentNewCore

final class InstrumentNewTests: XCTestCase {
    func testScaffoldsSpecMappingAndIndex() throws {
        let fm = FileManager.default
        let tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("instrument-new-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmpRoot, withIntermediateDirectories: true)

        // Seed empty mapping and instruments files
        let toolsDir = tmpRoot.appendingPathComponent("Tools", isDirectory: true)
        try fm.createDirectory(at: toolsDir, withIntermediateDirectories: true)
        let emptyArrayData = Data("[]".utf8)
        try emptyArrayData.write(to: toolsDir.appendingPathComponent("openapi-facts-mapping.json"))
        try emptyArrayData.write(to: toolsDir.appendingPathComponent("instruments.json"))

        let cfg = InstrumentNew.Config(
            appId: "llm-chat-test",
            agentId: "fountain.coach/agent/llm-chat-test/service",
            specName: "llm-chat-test.yml",
            visual: true,
            metalView: false,
            noApp: false
        )

        try InstrumentNew.generate(in: tmpRoot, config: cfg, dryRun: false)

        // Spec file created
        let specURL = tmpRoot
            .appendingPathComponent("Packages/FountainSpecCuration/openapi/v1", isDirectory: true)
            .appendingPathComponent("llm-chat-test.yml")
        XCTAssertTrue(fm.fileExists(atPath: specURL.path), "spec stub should be created")

        // Mapping contains new entry
        let mappingURL = toolsDir.appendingPathComponent("openapi-facts-mapping.json")
        let mappingData = try Data(contentsOf: mappingURL)
        let mappings = try JSONDecoder().decode([InstrumentNew.Mapping].self, from: mappingData)
        XCTAssertTrue(
            mappings.contains(where: { $0.spec == cfg.specName && $0.agentId == cfg.agentId }),
            "mapping should include spec/agentId pair"
        )

        // Instruments index contains new entry
        let instrumentsURL = toolsDir.appendingPathComponent("instruments.json")
        let instrumentsData = try Data(contentsOf: instrumentsURL)
        let entries = try JSONDecoder().decode([InstrumentNew.InstrumentIndexEntry].self, from: instrumentsData)
        XCTAssertTrue(
            entries.contains(where: { $0.appId == cfg.appId && $0.agentId == cfg.agentId }),
            "instruments index should include new appId/agentId"
        )
    }

    func testScaffoldsSeedTargetAndSourcesWhenFountainAppsPresent() throws {
        let fm = FileManager.default
        let tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("instrument-new-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmpRoot, withIntermediateDirectories: true)

        // Seed empty mapping and instruments files
        let toolsDir = tmpRoot.appendingPathComponent("Tools", isDirectory: true)
        try fm.createDirectory(at: toolsDir, withIntermediateDirectories: true)
        let emptyArrayData = Data("[]".utf8)
        try emptyArrayData.write(to: toolsDir.appendingPathComponent("openapi-facts-mapping.json"))
        try emptyArrayData.write(to: toolsDir.appendingPathComponent("instruments.json"))

        // Copy FountainApps manifest into the temp root so we can patch it safely.
        let testFileURL = URL(fileURLWithPath: #filePath)
        var repoRoot = testFileURL.deletingLastPathComponent()
        let fmRoot = FileManager.default
        for _ in 0..<10 {
            repoRoot.deleteLastPathComponent()
            var isDir: ObjCBool = false
            let pkg = repoRoot.appendingPathComponent("Package.swift", isDirectory: false)
            let packagesDir = repoRoot.appendingPathComponent("Packages", isDirectory: true)
            if fmRoot.fileExists(atPath: pkg.path)
                && fmRoot.fileExists(atPath: packagesDir.path, isDirectory: &isDir)
                && isDir.boolValue
            {
                break
            }
        }
        let sourcePackage = repoRoot
            .appendingPathComponent("Packages/FountainApps/Package.swift", isDirectory: false)
        XCTAssertTrue(fm.fileExists(atPath: sourcePackage.path), "expected Packages/FountainApps/Package.swift to exist in repo")

        let destPackageDir = tmpRoot
            .appendingPathComponent("Packages/FountainApps", isDirectory: true)
        try fm.createDirectory(at: destPackageDir, withIntermediateDirectories: true)
        let destPackage = destPackageDir.appendingPathComponent("Package.swift", isDirectory: false)
        try fm.copyItem(at: sourcePackage, to: destPackage)

        let cfg = InstrumentNew.Config(
            appId: "llm-chat-test",
            agentId: "fountain.coach/agent/llm-chat-test/service",
            specName: "llm-chat-test.yml",
            visual: true,
            metalView: false,
            noApp: false
        )

        try InstrumentNew.generate(in: tmpRoot, config: cfg, dryRun: false)

        // Seeder source created
        let seedMain = tmpRoot
            .appendingPathComponent("Packages/FountainApps/Sources/llm-chat-test-seed/main.swift", isDirectory: false)
        XCTAssertTrue(fm.fileExists(atPath: seedMain.path), "seed main.swift should be created")

        // Tests module created
        let testsDir = tmpRoot
            .appendingPathComponent("Packages/FountainApps/Tests/LlmChatTestTests", isDirectory: true)
        var isDir: ObjCBool = false
        XCTAssertTrue(
            fm.fileExists(atPath: testsDir.path, isDirectory: &isDir) && isDir.boolValue,
            "tests directory for LlmChatTestTests should be created"
        )
        let surfaceTests = testsDir.appendingPathComponent("LlmChatTestSurfaceTests.swift", isDirectory: false)
        XCTAssertTrue(fm.fileExists(atPath: surfaceTests.path), "surface tests file should be created")

        // App sources created
        let appMain = tmpRoot
            .appendingPathComponent("Packages/FountainApps/Sources/llm-chat-test-app/AppMain.swift", isDirectory: false)
        XCTAssertTrue(fm.fileExists(atPath: appMain.path), "app AppMain.swift should be created")

        // Manifest contains a new executable target for <appId>-seed, a testTarget for <AppId>Tests, and an app target
        let manifest = try String(contentsOf: destPackage)
        XCTAssertTrue(
            manifest.contains("name: \"llm-chat-test-seed\""),
            "manifest should contain executableTarget for llm-chat-test-seed"
        )
        XCTAssertTrue(
            manifest.contains("Sources/llm-chat-test-seed"),
            "manifest should point seed target at Sources/llm-chat-test-seed"
        )
        XCTAssertTrue(
            manifest.contains("name: \"LlmChatTestTests\""),
            "manifest should contain testTarget for LlmChatTestTests"
        )
        XCTAssertTrue(
            manifest.contains("Tests/LlmChatTestTests"),
            "manifest should point test target at Tests/LlmChatTestTests"
        )
        XCTAssertTrue(
            manifest.contains("name: \"llm-chat-test-app\""),
            "manifest should contain executableTarget for llm-chat-test-app"
        )
        XCTAssertTrue(
            manifest.contains("Sources/llm-chat-test-app"),
            "manifest should point app target at Sources/llm-chat-test-app"
        )
    }
}
