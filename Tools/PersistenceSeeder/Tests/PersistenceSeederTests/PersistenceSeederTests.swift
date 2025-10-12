import XCTest
@testable import PersistenceSeeder

final class PersistenceSeederTests: XCTestCase {
    func testManifestGeneration() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create sample markdown with front matter
        let textDir = tempDir.appendingPathComponent("texts")
        try FileManager.default.createDirectory(at: textDir, withIntermediateDirectories: true)
        let mdURL = textDir.appendingPathComponent("sample.md")
        let mdContent = """
        ---
        id: sample-1
        title: Sample
        language: en
        ---
        Body text.
        """
        try mdContent.write(to: mdURL, atomically: true, encoding: .utf8)

        // JSON annotation
        let annotationsDir = tempDir.appendingPathComponent("annotations")
        try FileManager.default.createDirectory(at: annotationsDir, withIntermediateDirectories: true)
        let jsonURL = annotationsDir.appendingPathComponent("note.json")
        try "{\"id\":\"a1\"}".write(to: jsonURL, atomically: true, encoding: .utf8)

        // Audio file
        let audioDir = tempDir.appendingPathComponent("audio")
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let audioURL = audioDir.appendingPathComponent("clip.mid")
        try Data([0,1,2,3]).write(to: audioURL)

        let seeder = PersistenceSeeder()
        let outputDir = tempDir.appendingPathComponent("out")
        let manifest = try seeder.seed(repoPath: tempDir.path, corpusId: "test-corpus", sourceRepo: "https://example.com/repo", output: outputDir)

        XCTAssertEqual(manifest.corpusId, "test-corpus")
        XCTAssertEqual(manifest.documents.count, 1)
        XCTAssertEqual(manifest.annotations.count, 1)
        XCTAssertEqual(manifest.audio.count, 1)

        let manifestURL = outputDir.appendingPathComponent("seed-manifest.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))
    }
}
