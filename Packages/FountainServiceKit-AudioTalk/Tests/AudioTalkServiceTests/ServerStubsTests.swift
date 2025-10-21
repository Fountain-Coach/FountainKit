import XCTest
@testable import AudioTalkService

final class ServerStubsTests: XCTestCase {
    func testHealthOK() async throws {
        let api = AudioTalkOpenAPI(state: AudioTalkState())
        let out = try await api.getAudioTalkHealth(Operations.getAudioTalkHealth.Input())
        switch out {
        case .ok:
            XCTAssertTrue(true)
        case .undocumented(let status, _):
            XCTAssertEqual(status, 200)
        default:
            XCTFail("Expected .ok or 200 undocumented from getAudioTalkHealth")
        }
    }
}
