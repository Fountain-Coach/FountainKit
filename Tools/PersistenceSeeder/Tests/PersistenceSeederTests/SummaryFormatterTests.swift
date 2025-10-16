import XCTest
@testable import PersistenceSeederKit

final class SummaryFormatterTests: XCTestCase {
    func testSummaryIncludesCountsAndSample() {
        let now = Date(timeIntervalSince1970: 0)
        let documents = [
            SeedManifest.FileEntry(path: "texts/one.md", sha256: "abc", size: 10, metadata: ["type": "document"]),
            SeedManifest.FileEntry(path: "texts/two.md", sha256: "def", size: 20, metadata: ["type": "document"])
        ]
        let translations = [
            SeedManifest.FileEntry(path: "translations/es.md", sha256: "ghi", size: 30, metadata: ["type": "translation"])
        ]
        let annotations = [
            SeedManifest.FileEntry(path: "annotations/note.json", sha256: "jkl", size: 15, metadata: ["type": "annotation"])
        ]
        let audio = [
            SeedManifest.FileEntry(path: "audio/clip.mid", sha256: "mno", size: 200, metadata: ["type": "artifact"])
        ]
        let manifest = SeedManifest(
            corpusId: "test-corpus",
            sourceRepo: "https://example.com/the-four-stars",
            generatedAt: now,
            documents: documents,
            translations: translations,
            annotations: annotations,
            audio: audio
        )
        let speeches = [
            FountainPlayParser.Speech(
                act: "I",
                scene: "I",
                location: "Orchard",
                speaker: "ORLANDO",
                lines: ["0123456789ABC"],
                index: 1
            )
        ]
        let result = SeedResult(manifest: manifest, speeches: speeches)
        let formatter = ManifestSummaryFormatter(snippetLimit: 10)

        let summary = formatter.format(result: result)

        XCTAssertTrue(summary.contains("Corpus: test-corpus (source: https://example.com/the-four-stars)"))
        XCTAssertTrue(summary.contains("Generated At: 1970-01-01T00:00:00.000Z"))
        XCTAssertTrue(summary.contains("Documents: 2"))
        XCTAssertTrue(summary.contains("Translations: 1"))
        XCTAssertTrue(summary.contains("Annotations: 1"))
        XCTAssertTrue(summary.contains("Audio: 1"))
        XCTAssertTrue(summary.contains("Derived Speeches: 1"))
        XCTAssertTrue(summary.contains("Sample: [ORLANDO] Act I Scene I – 0123456789…"))
    }

    func testSummaryOmitsSampleWhenNoSpeeches() {
        let manifest = SeedManifest(
            corpusId: "empty-corpus",
            sourceRepo: "https://example.com/the-four-stars",
            generatedAt: Date(timeIntervalSince1970: 0),
            documents: [],
            translations: [],
            annotations: [],
            audio: []
        )
        let result = SeedResult(manifest: manifest, speeches: [])
        let formatter = ManifestSummaryFormatter()

        let summary = formatter.format(result: result)

        XCTAssertFalse(summary.contains("Sample:"))
    }
}
