import XCTest
@testable import patchbay_service

final class ServiceHandlersTests: XCTestCase {
    func testSuggestLinksFindsCommonProperties() async throws {
        let h = PatchBayHandlers()
        // Sanity: default seed has triangle + quad with shared 'zoom'
        let out = try await h.suggestLinks(.init(body: .json(.init(nodeIds: nil, includeUMP: true))))
        switch out {
        case .ok(let ok):
            let suggestions = try ok.body.json
            XCTAssertTrue(suggestions.contains(where: { $0.reason.contains("zoom") }))
        default:
            XCTFail("Unexpected response")
        }
    }

    func testVendorIdentityPutGetRoundtrip() async throws {
        let h = PatchBayHandlers()
        // Put
        let v = Components.Schemas.VendorIdentity(manufacturerId: "0x7D", familyCode: 1, modelCode: 2, revision: 3, subtreeStrategy: .sequential)
        _ = try await h.putVendorIdentity(.init(body: .json(v)))
        // Get
        let out = try await h.getVendorIdentity(.init())
        switch out {
        case .ok(let ok):
            let got = try ok.body.json
            XCTAssertEqual(got.manufacturerId, "0x7D")
            XCTAssertEqual(got.familyCode, 1)
        default:
            XCTFail("Unexpected response")
        }
    }
}

