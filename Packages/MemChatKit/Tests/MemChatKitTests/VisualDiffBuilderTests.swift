import XCTest
import SemanticBrowserAPI
@testable import MemChatKit

final class VisualDiffBuilderTests: XCTestCase {
    func testClassificationMarksCoveredWithOverlap() {
        // Analysis with one block and one rect
        let r = SemanticBrowserAPI.Components.Schemas.Block.rectsPayloadPayload(imageId: "img-1", x: 0.1, y: 0.1, w: 0.2, h: 0.2, excerpt: nil, confidence: 0.9)
        let b = SemanticBrowserAPI.Components.Schemas.Block(id: "p0", kind: .paragraph, level: nil, text: "Hello world from Fountain", rects: [r], span: [0, 5], table: nil)
        let env = SemanticBrowserAPI.Components.Schemas.Analysis.envelopePayload(id: "e1", source: .init(uri: "https://example.com", fetchedAt: nil), contentType: "text/html", language: "en", bytes: nil, diagnostics: nil)
        let sums = SemanticBrowserAPI.Components.Schemas.Analysis.summariesPayload(abstract: nil, keyPoints: nil, tl_semi_dr: nil)
        let prov = SemanticBrowserAPI.Components.Schemas.Analysis.provenancePayload(pipeline: "test", model: nil)
        let analysis = SemanticBrowserAPI.Components.Schemas.Analysis(envelope: env, blocks: [b], semantics: nil, summaries: sums, provenance: prov)
        let res = VisualDiffBuilder.classify(analysis: analysis, imageId: "img-1", evidenceTexts: ["Fountain proves hello world"])
        XCTAssertEqual(res.covered.count, 1)
        XCTAssertEqual(res.missing.count, 0)
    }
}

