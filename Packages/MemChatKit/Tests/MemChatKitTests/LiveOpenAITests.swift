import XCTest
@testable import MemChatKit

final class LiveOpenAITests: XCTestCase {
    /// Optional, opt-in live test that sends a real chat request to OpenAI.
    /// Skips unless both MEMCHAT_LIVE_OPENAI=1 and OPENAI_API_KEY are set.
    @MainActor
    func testLiveOpenAIChatIfEnabled() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["MEMCHAT_LIVE_OPENAI"] == "1" else { throw XCTSkip("MEMCHAT_LIVE_OPENAI not enabled") }
        guard let key = env["OPENAI_API_KEY"], !key.isEmpty else { throw XCTSkip("OPENAI_API_KEY not set") }

        let cfg = MemChatConfiguration(memoryCorpusId: "memchat-live-test", model: "gpt-4o-mini", openAIAPIKey: key)
        let controller = MemChatController(config: cfg)
        controller.newChat()
        controller.send("Reply with a short greeting.")

        // Wait up to ~30s for a turn to be appended
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if let last = controller.turns.last, !last.answer.isEmpty {
                XCTAssertFalse(last.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                return
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        XCTFail("No answer received from OpenAI within timeout")
    }
}

