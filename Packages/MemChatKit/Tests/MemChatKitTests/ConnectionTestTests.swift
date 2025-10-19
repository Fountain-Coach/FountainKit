import XCTest
@testable import MemChatKit

final class ConnectionTestTests: XCTestCase {
    /// Live /v1/models probe against OpenAI; skips when OPENAI_API_KEY is not set.
    func testModelsEndpointOKWithOpenAI() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let key = env["OPENAI_API_KEY"], !key.isEmpty else { throw XCTSkip("OPENAI_API_KEY not set") }
        let endpoint = ProviderResolver.openAIChatURL
        let result = await ConnectionTester.test(apiKey: key, endpoint: endpoint)
        if case .ok = result { } else { XCTFail("expected ok, got \(result)") }
    }
}
