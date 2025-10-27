import XCTest
@testable import patchbay_app

@MainActor
final class AppViewTests: XCTestCase {
    final class MockAPI: PatchBayAPI {
        func listInstruments() async throws -> [Components.Schemas.Instrument] {
            let schema = Components.Schemas.PropertySchema(version: 1, properties: [
                .init(name: "zoom", _type: .float)
            ])
            let ident = Components.Schemas.InstrumentIdentity(manufacturer: "Fountain", product: "Mock", displayName: "Mock#1", instanceId: "m1", muid28: 0, hasUMPInput: true, hasUMPOutput: true)
            let a = Components.Schemas.Instrument(
                id: "A", kind: .init(rawValue: "mvk.triangle")!, title: "A",
                x: 0, y: 0, w: 100, h: 80,
                identity: ident, propertySchema: schema
            )
            let b = Components.Schemas.Instrument(
                id: "B", kind: .init(rawValue: "mvk.quad")!, title: "B",
                x: 0, y: 0, w: 100, h: 80,
                identity: ident, propertySchema: schema
            )
            return [a, b]
        }
        func suggestLinks(nodeIds: [String]) async throws -> [Components.Schemas.SuggestedLink] {
            let l = Components.Schemas.CreateLink(kind: .property, property: .init(from: "A.zoom", to: "B.zoom", direction: .a_to_b), ump: nil)
            return [.init(link: l, reason: "matched property zoom", confidence: 0.9)]
        }
        func createInstrument(id: String, kind: Components.Schemas.InstrumentKind, title: String?, x: Int, y: Int, w: Int, h: Int) async throws -> Components.Schemas.Instrument? {
            return nil
        }
    }

    func testAutoNoodleProducesSuggestions() async throws {
        let state = AppState(api: MockAPI())
        await state.refresh()
        await state.autoNoodle()
        XCTAssertFalse(state.suggestions.isEmpty)
        XCTAssertTrue(state.suggestions.first?.reason.contains("zoom") == true)
    }
}
