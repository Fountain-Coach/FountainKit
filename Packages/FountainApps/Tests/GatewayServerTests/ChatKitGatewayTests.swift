import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import ChatKitGatewayPlugin

@testable import gateway_server

final class ChatKitGatewayTests: XCTestCase {
    func startGateway() async -> ServerTestUtils.RunningServer {
        await ServerTestUtils.startGateway(on: 18121, plugins: [ChatKitGatewayPlugin()])
    }

    func testChatKitSessionStartReturnsSecret() async throws {
        let running = await startGateway()
        defer { Task { await running.stop() } }

        let url = URL(string: "http://127.0.0.1:\(running.port)/chatkit/session")!
        let (data, response) = try await ServerTestUtils.httpJSON("POST", url)
        XCTAssertEqual(response.statusCode, 201, "expected session creation")

        struct Session: Decodable {
            let client_secret: String
            let session_id: String
            let expires_at: String
        }

        let session = try JSONDecoder().decode(Session.self, from: data)
        XCTAssertFalse(session.client_secret.isEmpty)
        XCTAssertFalse(session.session_id.isEmpty)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertNotNil(formatter.date(from: session.expires_at))
    }

    func testChatKitSessionRefreshRevokesPreviousSecret() async throws {
        let running = await startGateway()
        defer { Task { await running.stop() } }

        let sessionURL = URL(string: "http://127.0.0.1:\(running.port)/chatkit/session")!
        let (sessionData, sessionResp) = try await ServerTestUtils.httpJSON("POST", sessionURL)
        XCTAssertEqual(sessionResp.statusCode, 201)

        struct Session: Decodable { let client_secret: String }
        let initial = try JSONDecoder().decode(Session.self, from: sessionData)

        let refreshURL = URL(string: "http://127.0.0.1:\(running.port)/chatkit/session/refresh")!
        let (refreshData, refreshResp) = try await ServerTestUtils.httpJSON(
            "POST",
            refreshURL,
            body: ["client_secret": initial.client_secret]
        )
        XCTAssertEqual(refreshResp.statusCode, 200, String(data: refreshData, encoding: .utf8) ?? "")

        let refreshed = try JSONDecoder().decode(Session.self, from: refreshData)
        XCTAssertNotEqual(refreshed.client_secret, initial.client_secret)

        // Attempt to refresh using the old secret again should now fail.
        let (_, secondResp) = try await ServerTestUtils.httpJSON(
            "POST",
            refreshURL,
            body: ["client_secret": initial.client_secret]
        )
        XCTAssertEqual(secondResp.statusCode, 401)
    }

    func testGatewayOpenAPIDocumentIncludesChatKitPaths() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let testsFolder = testFile.deletingLastPathComponent() // ChatKitGatewayTests.swift directory
        let packageRoot = testsFolder
            .deletingLastPathComponent() // GatewayServerTests
            .deletingLastPathComponent() // Tests
        let openapiURL = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("gateway-server")
            .appendingPathComponent("openapi.yaml")
        let contents = try String(contentsOf: openapiURL)
        XCTAssertTrue(contents.contains("/chatkit/session"))
        XCTAssertTrue(contents.contains("/chatkit/messages"))
        XCTAssertTrue(contents.contains("/chatkit/upload"))
    }
}
