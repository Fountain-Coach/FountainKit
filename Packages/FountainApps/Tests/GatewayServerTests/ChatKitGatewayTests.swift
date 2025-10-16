import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import ChatKitGatewayPlugin

@testable import gateway_server

final class ChatKitGatewayTests: XCTestCase {
    private struct Session: Decodable {
        let client_secret: String
        let session_id: String
        let expires_at: String
    }

    private struct UploadResponse: Decodable {
        let attachment_id: String
        let upload_url: String
        let mime_type: String?
    }

    func startGateway() async -> ServerTestUtils.RunningServer {
        await ServerTestUtils.startGateway(on: 18121, plugins: [ChatKitGatewayPlugin()])
    }

    private func createSession(on port: Int) async throws -> Session {
        let url = URL(string: "http://127.0.0.1:\(port)/chatkit/session")!
        let (data, response) = try await ServerTestUtils.httpJSON("POST", url)
        XCTAssertEqual(response.statusCode, 201)
        return try JSONDecoder().decode(Session.self, from: data)
    }

    private func makeMultipartBody(boundary: String, parts: [(name: String, filename: String?, contentType: String?, data: Data)]) -> Data {
        var body = Data()
        let lineBreak = "\r\n"
        for part in parts {
            body.append(Data("--\(boundary)\r\n".utf8))
            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let filename = part.filename {
                disposition += "; filename=\"\(filename)\""
            }
            body.append(Data((disposition + lineBreak).utf8))
            if let contentType = part.contentType {
                body.append(Data("Content-Type: \(contentType)\r\n".utf8))
            }
            body.append(Data(lineBreak.utf8))
            body.append(part.data)
            body.append(Data(lineBreak.utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    func testChatKitSessionStartReturnsSecret() async throws {
        let running = await startGateway()
        defer { Task { await running.stop() } }

        let session = try await createSession(on: running.port)
        XCTAssertFalse(session.client_secret.isEmpty)
        XCTAssertFalse(session.session_id.isEmpty)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertNotNil(formatter.date(from: session.expires_at))
    }

    func testChatKitSessionRefreshRevokesPreviousSecret() async throws {
        let running = await startGateway()
        defer { Task { await running.stop() } }

        let initial = try await createSession(on: running.port)

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

    func testChatKitMessageStreamingEchoesUserPrompt() async throws {
        let running = await startGateway()
        defer { Task { await running.stop() } }

        let session = try await createSession(on: running.port)
        let body: [String: Any] = [
            "client_secret": session.client_secret,
            "messages": [["role": "user", "content": "Hello Fountain"]],
            "stream": true
        ]

        let messageURL = URL(string: "http://127.0.0.1:\(running.port)/chatkit/messages")!
        var request = URLRequest(url: messageURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 202)
        XCTAssertEqual((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"), "text/event-stream")

        guard let sse = String(data: data, encoding: .utf8) else {
            return XCTFail("expected utf8 body")
        }
        XCTAssertTrue(sse.contains("event: delta"))
        XCTAssertTrue(sse.contains("Hello Fountain"))
        XCTAssertTrue(sse.contains("event: completion"))
        XCTAssertTrue(sse.contains("\"done\":true"))
    }

    func testChatKitMessageNonStreamingReturnsJSON() async throws {
        let running = await startGateway()
        defer { Task { await running.stop() } }

        let session = try await createSession(on: running.port)
        let body: [String: Any] = [
            "client_secret": session.client_secret,
            "messages": [["role": "user", "content": "Non stream"]],
            "stream": false
        ]

        let messageURL = URL(string: "http://127.0.0.1:\(running.port)/chatkit/messages")!
        let (data, response) = try await ServerTestUtils.httpJSON("POST", messageURL, body: body)
        XCTAssertEqual(response.statusCode, 200)

        struct MessageResponse: Decodable {
            let answer: String
            let thread_id: String
            let response_id: String
            let created_at: String
        }

        let decoded = try JSONDecoder().decode(MessageResponse.self, from: data)
        XCTAssertEqual(decoded.answer, "Non stream")
        XCTAssertFalse(decoded.response_id.isEmpty)
        XCTAssertFalse(decoded.thread_id.isEmpty)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertNotNil(formatter.date(from: decoded.created_at))
    }

    func testChatKitMessageRejectsInvalidSecret() async throws {
        let running = await startGateway()
        defer { Task { await running.stop() } }

        let body: [String: Any] = [
            "client_secret": "bogus",
            "messages": [["role": "user", "content": "hi"]]
        ]
        let messageURL = URL(string: "http://127.0.0.1:\(running.port)/chatkit/messages")!
        let (_, response) = try await ServerTestUtils.httpJSON("POST", messageURL, body: body)
        XCTAssertEqual(response.statusCode, 401)
    }

    func testChatKitUploadStoresAttachment() async throws {
        let running = await startGateway()
        defer { Task { await running.stop() } }

        let session = try await createSession(on: running.port)
        let boundary = "Boundary-" + UUID().uuidString
        let fileData = Data("Uploaded text".utf8)
        let multipart = makeMultipartBody(boundary: boundary, parts: [
            (name: "client_secret", filename: nil, contentType: nil, data: Data(session.client_secret.utf8)),
            (name: "thread_id", filename: nil, contentType: nil, data: Data("thread-123".utf8)),
            (name: "file", filename: "note.txt", contentType: "text/plain", data: fileData)
        ])

        let uploadURL = URL(string: "http://127.0.0.1:\(running.port)/chatkit/upload")!
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipart

        let (data, response) = try await URLSession.shared.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode != 201 {
            let debug = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            XCTFail("upload failed: status=\((response as? HTTPURLResponse)?.statusCode ?? -1) body=\(debug)")
            return
        }
        XCTAssertEqual((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let decoded = try JSONDecoder().decode(UploadResponse.self, from: data)
        XCTAssertFalse(decoded.attachment_id.isEmpty)
        XCTAssertTrue(decoded.upload_url.starts(with: "memory://chatkit-attachments/"))
        XCTAssertEqual(decoded.mime_type, "text/plain")
    }

    func testChatKitUploadRejectsInvalidSecret() async throws {
        let running = await startGateway()
        defer { Task { await running.stop() } }

        let boundary = "Boundary-" + UUID().uuidString
        let multipart = makeMultipartBody(boundary: boundary, parts: [
            (name: "client_secret", filename: nil, contentType: nil, data: Data("bad".utf8)),
            (name: "file", filename: "note.txt", contentType: "text/plain", data: Data("content".utf8))
        ])

        let uploadURL = URL(string: "http://127.0.0.1:\(running.port)/chatkit/upload")!
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipart

        let (data, response) = try await URLSession.shared.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode != 401 {
            let debug = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            XCTFail("expected 401, got \((response as? HTTPURLResponse)?.statusCode ?? -1) body=\(debug)")
        }
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
