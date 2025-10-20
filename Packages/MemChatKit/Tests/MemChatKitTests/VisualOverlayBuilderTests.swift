import XCTest
import SemanticBrowserAPI
@testable import MemChatKit

final class VisualOverlayBuilderTests: XCTestCase {
    func testFiltersByImageIdAndNormalizes() throws {
        // Build a tiny analysis with two blocks and mixed imageIds
        let r1 = SemanticBrowserAPI.Components.Schemas.Block.rectsPayloadPayload(imageId: "img-a", x: 0.1, y: 0.2, w: 0.3, h: 0.4, excerpt: nil, confidence: 0.9)
        let r2 = SemanticBrowserAPI.Components.Schemas.Block.rectsPayloadPayload(imageId: "synthetic", x: 0.5, y: 0.5, w: 0.4, h: 0.4, excerpt: nil, confidence: 0.5)
        let b1 = SemanticBrowserAPI.Components.Schemas.Block(id: "p0", kind: .paragraph, level: nil, text: "A", rects: [r1, r2], span: [0, 1], table: nil)
        let r3 = SemanticBrowserAPI.Components.Schemas.Block.rectsPayloadPayload(imageId: "img-a", x: 0.0, y: 0.0, w: 0.1, h: 0.1, excerpt: nil, confidence: 0.9)
        let b2 = SemanticBrowserAPI.Components.Schemas.Block(id: "p1", kind: .paragraph, level: nil, text: "B", rects: [r3], span: [0, 1], table: nil)
        let env = SemanticBrowserAPI.Components.Schemas.Analysis.envelopePayload(id: "e1", source: .init(uri: "https://example.com", fetchedAt: nil), contentType: "text/html", language: "en", bytes: nil, diagnostics: nil)
        let sums = SemanticBrowserAPI.Components.Schemas.Analysis.summariesPayload(abstract: nil, keyPoints: nil, tl_semi_dr: nil)
        let prov = SemanticBrowserAPI.Components.Schemas.Analysis.provenancePayload(pipeline: "test", model: nil)
        let analysis = SemanticBrowserAPI.Components.Schemas.Analysis(envelope: env, blocks: [b1, b2], semantics: nil, summaries: sums, provenance: prov)
        let ovs = VisualOverlayBuilder.overlays(from: analysis, imageId: "img-a")
        XCTAssertEqual(ovs.count, 2)
        for ov in ovs {
            XCTAssertGreaterThan(ov.rect.width, 0)
            XCTAssertGreaterThan(ov.rect.height, 0)
            XCTAssertTrue(ov.rect.origin.x >= 0 && ov.rect.origin.x <= 1)
            XCTAssertTrue(ov.rect.origin.y >= 0 && ov.rect.origin.y <= 1)
        }
    }
}
