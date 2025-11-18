import XCTest
@testable import instrument_new

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
}
