import XCTest
@testable import MemChatKit

final class GatewayToggleTests: XCTestCase {
    @MainActor
    func testProviderLabelReflectsGatewaySelection() async throws {
        // Direct (no gateway)
        let directCfg = MemChatConfiguration(memoryCorpusId: "memchat-gw", model: "gpt-4o-mini", openAIAPIKey: "sk-test", gatewayURL: nil)
        let direct = MemChatController(config: directCfg)
        XCTAssertEqual(direct.providerLabel, "openai")

        // Gateway selected
        let gwURL = URL(string: "http://127.0.0.1:8010")!
        let gwCfg = MemChatConfiguration(memoryCorpusId: "memchat-gw", model: "gpt-4o-mini", openAIAPIKey: "sk-test", gatewayURL: gwURL)
        let gateway = MemChatController(config: gwCfg)
        XCTAssertEqual(gateway.providerLabel, "gateway")
    }

    @MainActor
    func testLiveGatewayChatIfEnabled() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["MEMCHAT_LIVE_GATEWAY"] == "1", let raw = env["GATEWAY_BASE_URL"], let url = URL(string: raw) else {
            throw XCTSkip("Live gateway test not enabled")
        }
        var req = URLRequest(url: url.appending(path: "/metrics")); req.httpMethod = "GET"; req.timeoutInterval = 3.0
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw XCTSkip("Gateway not reachable")
        }
        let cfg = MemChatConfiguration(memoryCorpusId: "memchat-gw", model: "gpt-4o-mini", openAIAPIKey: env["OPENAI_API_KEY"], gatewayURL: url)
        let controller = MemChatController(config: cfg)
        let result = await controller.testLiveChatRoundtrip()
        if case .ok(let preview) = result { XCTAssertFalse(preview.isEmpty) } else { XCTFail("gateway roundtrip failed: \(result)") }
    }
}

