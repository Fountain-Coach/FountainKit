import XCTest
@testable import MemChatKit

final class ConnectionTestTests: XCTestCase {
    final class MockClient: AnyHTTPClient {
        let status: Int
        init(status: Int) { self.status = status }
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(), resp)
        }
    }

    func testConnectionOKWithOpenAI() async {
        let endpoint = ProviderResolver.openAIChatURL
        let result = await ConnectionTester.test(apiKey: "sk-xyz", endpoint: endpoint, client: MockClient(status: 200))
        if case .ok = result { } else { XCTFail("expected ok, got \(result)") }
    }

    func testConnectionFailWithLocal404() async {
        let local = URL(string: "http://127.0.0.1:11434/v1/chat/completions")!
        let result = await ConnectionTester.test(apiKey: nil, endpoint: local, client: MockClient(status: 404))
        if case .fail(let msg) = result { XCTAssertTrue(msg.contains("HTTP 404")) } else { XCTFail("expected fail") }
    }
}
