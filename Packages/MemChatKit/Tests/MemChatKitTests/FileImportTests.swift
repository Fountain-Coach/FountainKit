import XCTest
import Foundation
import FountainStoreClient
@testable import MemChatKit

final class FileImportTests: XCTestCase {
    private func makeController(corpus: String = "memchat-import-test") async -> (MemChatController, FountainStoreClient) {
        let embedded = EmbeddedFountainStoreClient()
        let store = FountainStoreClient(client: embedded)
        let cfg = MemChatConfiguration(memoryCorpusId: corpus, model: "gpt-4o-mini", openAIAPIKey: nil)
        let controller = await MainActor.run { MemChatController(config: cfg, store: store) }
        return (controller, store)
    }

    func testImportTextCreatesPageAndSegments() async throws {
        let (c, store) = await makeController()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("import.txt")
        let text = Array(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 60).joined()
        try text.write(to: tmp, atomically: true, encoding: .utf8)

        let ok = await c.ingestFiles([tmp])
        XCTAssertTrue(ok)

        // Verify page exists
        let (pagesTotal, pages) = try await store.listPages(corpusId: c.config.memoryCorpusId, limit: 100, offset: 0)
        XCTAssertGreaterThan(pagesTotal, 0)
        XCTAssertTrue(pages.contains(where: { $0.pageId == "file:\(tmp.lastPathComponent)" }))

        // Verify chunked segments (expect > 1)
        let (segTotal, _) = try await store.listSegments(corpusId: c.config.memoryCorpusId, limit: 1000, offset: 0)
        XCTAssertGreaterThan(segTotal, 1)
    }

    func testImportHTMLStripsTags() async throws {
        let (c, store) = await makeController(corpus: "memchat-import-html")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("sample.html")
        let html = "<html><body><p>Hello <b>world</b></p></body></html>"
        try html.write(to: tmp, atomically: true, encoding: .utf8)

        let ok = await c.ingestFiles([tmp])
        XCTAssertTrue(ok)

        // Fetch segment text and assert tags are removed
        let (total, segs) = try await store.listSegments(corpusId: c.config.memoryCorpusId, limit: 10, offset: 0)
        XCTAssertGreaterThan(total, 0)
        let sample = try XCTUnwrap(segs.first)
        XCTAssertFalse(sample.text.contains("<"))
        XCTAssertTrue(sample.text.contains("Hello"))
    }

    func testEvidencePreviewReturnsSnippetsForFileHost() async throws {
        let (ctrl, _) = await makeController(corpus: "memchat-preview")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("evidence.txt")
        try "Alpha Beta Gamma".write(to: tmp, atomically: true, encoding: .utf8)
        _ = await ctrl.ingestFiles([tmp])
        let items = await ctrl.evidencePreview(host: "file", depthLevel: 1)
        XCTAssertGreaterThan(items.count, 0)
    }
}
