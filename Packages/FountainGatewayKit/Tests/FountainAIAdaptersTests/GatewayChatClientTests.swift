import XCTest
@testable import FountainAIAdapters
import LLMGatewayAPI

final class GatewayChatClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        MockURLProtocol.requestHandler = nil
    }

    func testStreamYieldsChunksFromServerSentEvents() async throws {
        let ssePayload = """
        data: {"delta":{"content":"Hello "}}

        data: {"answer":"Hello world","provider":"openai","model":"gpt-4o-mini"}

        data: [DONE]

        """
        let expectation = expectation(description: "received request")

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.query?.contains("stream=1") ?? false)
            expectation.fulfill()
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return .init(response: response, data: Data(ssePayload.utf8))
        }

        let client = GatewayChatClient(
            baseURL: URL(string: "https://example.com")!,
            tokenProvider: { "secret" },
            session: makeSession()
        )

        let request = ChatRequest(model: "gpt-4o-mini", messages: [
            .init(role: "user", content: "Hello?")
        ])

        var iterator = client.stream(request: request).makeAsyncIterator()
        let first = try await iterator.next()
        XCTAssertEqual(first?.text, "Hello ")
        XCTAssertEqual(first?.isFinal, false)

        let second = try await iterator.next()
        XCTAssertEqual(second?.text, "Hello world")
        XCTAssertEqual(second?.isFinal, true)
        XCTAssertEqual(second?.response?.answer, "Hello world")
        XCTAssertEqual(second?.response?.provider, "openai")

        let finished = try await iterator.next()
        XCTAssertNil(finished)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testCompleteReturnsJSONResponse() async throws {
        let payload = """
        {
          "answer": "All good",
          "provider": "openai",
          "model": "gpt-4o"
        }
        """

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return .init(response: response, data: Data(payload.utf8))
        }

        let client = GatewayChatClient(
            baseURL: URL(string: "https://example.com")!,
            tokenProvider: { nil },
            session: makeSession()
        )

        let response = try await client.complete(
            request: ChatRequest(model: "gpt-4o", messages: [.init(role: "user", content: "Ping!")])
        )
        XCTAssertEqual(response.answer, "All good")
        XCTAssertEqual(response.model, "gpt-4o")
        XCTAssertEqual(response.provider, "openai")
    }

    func testNon2xxStatusThrowsServerError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = Data("{\"error\":\"unauthorized\"}".utf8)
            return .init(response: response, data: data)
        }

        let client = GatewayChatClient(
            baseURL: URL(string: "https://example.com")!,
            tokenProvider: { nil },
            session: makeSession()
        )
        let request = ChatRequest(model: "gpt-4o", messages: [.init(role: "user", content: "Hi")])

        await XCTAssertThrowsErrorAsync(try await client.complete(request: request)) { error in
            guard case GatewayChatError.serverError(let status, let message) = error else {
                XCTFail("Unexpected error \(error)")
                return
            }
            XCTAssertEqual(status, 401)
            XCTAssertEqual(message, "{\"error\":\"unauthorized\"}")
        }
    }
}

// MARK: - Helpers

private func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class MockURLProtocol: URLProtocol {
    struct MockResponse {
        let response: HTTPURLResponse
        let data: Data
    }

    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> MockResponse)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "MockURLProtocol", code: -1))
            return
        }
        do {
            let mock = try handler(request)
            client?.urlProtocol(self, didReceive: mock.response, cacheStoragePolicy: .notAllowed)
            if !mock.data.isEmpty {
                client?.urlProtocol(self, didLoad: mock.data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension XCTestCase {
    func XCTAssertThrowsErrorAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ errorHandler: (Error) -> Void = { _ in }
    ) async {
        do {
            _ = try await expression()
            XCTFail(message(), file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }
}
