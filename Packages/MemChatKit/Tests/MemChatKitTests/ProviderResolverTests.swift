import XCTest
@testable import MemChatKit

final class ProviderResolverTests: XCTestCase {
    func testOpenAISelectedWhenKeyPresent() {
        let sel = ProviderResolver.selectProvider(apiKey: "sk-123", openAIEndpoint: nil, localEndpoint: nil)
        XCTAssertNotNil(sel)
        XCTAssertEqual(sel?.label, "openai")
        XCTAssertTrue(sel!.usesAPIKey)
        XCTAssertTrue((sel?.endpoint.host ?? "").contains("openai.com"))
    }

    func testLocalSelectedWhenNoKey() {
        let url = URL(string: "http://127.0.0.1:11434/v1/chat/completions")!
        let sel = ProviderResolver.selectProvider(apiKey: nil, openAIEndpoint: nil, localEndpoint: url)
        XCTAssertNotNil(sel)
        XCTAssertEqual(sel?.label, "local")
        XCTAssertFalse(sel!.usesAPIKey)
        XCTAssertEqual(sel?.endpoint, url)
    }

    func testOpenAIPreferredWhenKeyAndLocal() {
        let url = URL(string: "http://127.0.0.1:11434/v1/chat/completions")!
        let sel = ProviderResolver.selectProvider(apiKey: "sk-123", openAIEndpoint: nil, localEndpoint: url)
        XCTAssertNotNil(sel)
        XCTAssertEqual(sel?.label, "openai")
    }

    func testModelsURLBuilding() {
        let openAIChat = URL(string: "https://api.openai.com/v1/chat/completions")!
        XCTAssertEqual(ProviderResolver.modelsURL(for: openAIChat).path, "/v1/models")

        let localChat = URL(string: "http://127.0.0.1:11434/v1/chat/completions")!
        XCTAssertEqual(ProviderResolver.modelsURL(for: localChat).path, "/v1/models")

        let base = URL(string: "http://host/")!
        XCTAssertEqual(ProviderResolver.modelsURL(for: base).path, "/v1/models")
    }
}

