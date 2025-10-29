import XCTest
@testable import EngraverChatCore
@testable import engraver_chat_tui
import FountainAIAdapters
import ApiClientsCore

final class TranscriptFormatterTests: XCTestCase {
    func testFormatterSplitsMultilineMessages() {
        let formatter = TranscriptFormatter(transcriptLimit: 10, wrapWidth: nil)
        let date = Date(timeIntervalSince1970: 0)
        let turn = EngraverChatTurn(
            id: UUID(),
            sessionId: UUID(),
            createdAt: date,
            prompt: "Line one\nLine two",
            answer: "First answer line\nSecond answer line",
            provider: "mock-provider",
            model: "mock-model",
            tokens: [],
            response: GatewayChatResponse(
                answer: "First answer line\nSecond answer line",
                provider: "mock-provider",
                model: "mock-model",
                usage: nil,
                raw: nil,
                functionCall: nil
            )
        )
        let snapshot = ChatSnapshot(
            turns: [turn],
            activeTokens: [],
            diagnostics: [],
            state: .idle,
            lastError: nil,
            selectedModel: "mock-model",
            availableModels: ["mock-model"],
            corpusId: "test-corpus",
            collection: "chat-turns",
            sessionId: UUID(),
            sessionName: "Test Session",
            sessionStartedAt: date
        )

        let lines = formatter.lines(for: snapshot)
        XCTAssertTrue(lines.contains(where: { $0.contains("You ▸ Line one") }))
        XCTAssertTrue(lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == "Line two" }))
        XCTAssertTrue(lines.contains(where: { $0.contains("mock-provider ▸ First answer line") }))
        XCTAssertTrue(lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == "Second answer line" }))
    }

    func testFormatterWrapsLongLinesToWidth() {
        let formatter = TranscriptFormatter(transcriptLimit: 10, wrapWidth: 40)
        let date = Date(timeIntervalSince1970: 0)
        let turn = EngraverChatTurn(
            id: UUID(),
            sessionId: UUID(),
            createdAt: date,
            prompt: "This is a line that should exceed the wrap width and therefore appear across multiple lines in the transcript.",
            answer: "",
            provider: "mock-provider",
            model: "mock-model",
            tokens: [],
            response: GatewayChatResponse(
                answer: "",
                provider: "mock-provider",
                model: "mock-model",
                usage: nil,
                raw: nil,
                functionCall: nil
            )
        )
        let snapshot = ChatSnapshot(
            turns: [turn],
            activeTokens: [],
            diagnostics: [],
            state: .idle,
            lastError: nil,
            selectedModel: "mock-model",
            availableModels: ["mock-model"],
            corpusId: "test-corpus",
            collection: "chat-turns",
            sessionId: UUID(),
            sessionName: "Test Session",
            sessionStartedAt: date
        )

        let lines = formatter.lines(for: snapshot)
        XCTAssertTrue(lines.count >= 2)
        XCTAssertTrue(lines.contains(where: { $0.contains("You ▸ This is a line") }))
        XCTAssertTrue(lines.dropFirst().contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && line.first == " "
        })
    }
}

#endif // !ROBOT_ONLY
// Robot-only mode: exclude this suite when building robot tests
#if !ROBOT_ONLY
