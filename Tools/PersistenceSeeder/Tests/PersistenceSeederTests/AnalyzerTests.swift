import XCTest
@testable import PersistenceSeeder

final class AnalyzerTests: XCTestCase {
    func testAnalyzeProducesProfile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let mdURL = tempDir.appendingPathComponent("note.md")
        try """
        ---
        id: note-1
        author: test
        ---
        body
        """.write(to: mdURL, atomically: true, encoding: .utf8)

        let jsonURL = tempDir.appendingPathComponent("annotation.json")
        try "{\"kind\":\"test\"}".write(to: jsonURL, atomically: true, encoding: .utf8)

        let analyzer = RepositoryAnalyzer()
        let profile = try analyzer.analyze(repoPath: tempDir.path, maxSamples: 5)

        XCTAssertEqual(profile.totalFiles, 2)
        XCTAssertTrue(profile.extensions.keys.contains("md"))
        XCTAssertTrue(profile.extensions.keys.contains("json"))
        XCTAssertFalse(profile.samples.isEmpty)
    }
}
