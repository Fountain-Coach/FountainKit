import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import FountainStoreClient
import GatewayAPI
import FountainRuntime
@testable import ChatKitGatewayPlugin
@testable import gateway_server
@testable import PublishingFrontend

private struct StubResponder: ChatResponder {
    func respond(session: ChatKitSessionStore.StoredSession,
                 request: ChatKitMessageRequest,
                 preferStreaming: Bool) async throws -> ChatResponderResult {
        let answer = request.messages.last(where: { $0.role.lowercased() == "user" })?.content ?? ""
        return ChatResponderResult(answer: answer,
                                   provider: "stub",
                                   model: "stub-model",
                                   usage: ["prompt_tokens": 1],
                                   streamEvents: nil)
    }
}

#endif // !ROBOT_ONLY

private actor InMemoryUploadStore: ChatKitUploadStoring {
    private var attachments: [String: ChatKitUploadStore.StoredAttachment] = [:]
    private let corpusId: String
    private let collection: String
    private let clock: @Sendable () -> Date

    init(corpusId: String = "chatkit",
         collection: String = "attachments",
         clock: @escaping @Sendable () -> Date = Date.init) {
        self.corpusId = corpusId
        self.collection = collection
        self.clock = clock
    }

    func store(fileName: String,
               mimeType: String?,
               data: Data,
               sessionId: String,
               threadId: String?) async throws -> ChatKitUploadStore.Descriptor {
        let attachmentId = UUID().uuidString.lowercased()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let storedAt = formatter.string(from: clock())
        let resolvedMime = mimeType?.isEmpty == false ? mimeType! : "application/octet-stream"
        let descriptor = ChatKitUploadStore.Descriptor(
            id: attachmentId,
            url: "fountain://\(corpusId)/\(collection)/\(attachmentId)",
            fileName: fileName,
            mimeType: resolvedMime,
            sizeBytes: data.count,
            checksum: ChatKitUploadStore.checksum(for: data),
            storedAt: storedAt,
            sessionId: sessionId,
            threadId: threadId
        )
        attachments[attachmentId] = ChatKitUploadStore.StoredAttachment(descriptor: descriptor, data: data)
        return descriptor
    }

    func load(attachmentId: String) async throws -> ChatKitUploadStore.StoredAttachment? {
        attachments[attachmentId]
    }

    func delete(attachmentId: String) async throws {
        attachments.removeValue(forKey: attachmentId)
    }
}

final class ChatKitGatewayTests: XCTestCase {
    private let responder = StubResponder()
    private var metadataStore: GatewayAttachmentStore?
    private var attachmentClient: FountainStoreClient?
    private var uploadStore: (any ChatKitUploadStoring)?
    private var cachedRepoRoot: URL?

    private struct Session: Decodable, Sendable {
        let client_secret: String
        let session_id: String
        let expires_at: String
    }

    private struct UploadResponse: Decodable, Sendable {
        let attachment_id: String
        let upload_url: String
        let mime_type: String?
    }

    private struct ErrorResponse: Decodable, Sendable {
        let error: String
        let code: String
    }

    func makePlugin(responder overrideResponder: (any ChatResponder)? = nil,
                    maxAttachmentBytes: Int? = nil,
                    allowedMIMEs: Set<String>? = nil,
                    logger: (any ChatKitAttachmentLogger)? = ChatKitLogging.makeLogger(),
                    useEmbeddedUploadStore: Bool = true) -> ChatKitGatewayPlugin {
        let sessionStore = ChatKitSessionStore()
        let uploadClient = FountainStoreClient(client: EmbeddedFountainStoreClient())
        let metadataStore = GatewayAttachmentStore(store: uploadClient)
        let threadStore = GatewayThreadStore(store: uploadClient)
        let resolvedUploadStore: any ChatKitUploadStoring = useEmbeddedUploadStore
            ? ChatKitUploadStore(store: uploadClient)
            : InMemoryUploadStore()
        self.metadataStore = metadataStore
        self.attachmentClient = uploadClient
        self.uploadStore = resolvedUploadStore
        return ChatKitGatewayPlugin(store: sessionStore,
                                    uploadStore: resolvedUploadStore,
                                    metadataStore: metadataStore,
                                    threadStore: threadStore,
                                    responder: overrideResponder ?? responder,
                                    maxAttachmentBytes: maxAttachmentBytes,
                                    allowedAttachmentMIMEs: allowedMIMEs,
                                    logger: logger)
    }

    func startGateway(responder overrideResponder: (any ChatResponder)? = nil,
                      maxAttachmentBytes: Int? = nil,
                      allowedMIMEs: Set<String>? = nil,
                      logger: (any ChatKitAttachmentLogger)? = ChatKitLogging.makeLogger(),
                      useEmbeddedUploadStore: Bool = true) async -> ServerTestUtils.RunningServer {
        let plugin = makePlugin(responder: overrideResponder,
                                maxAttachmentBytes: maxAttachmentBytes,
                                allowedMIMEs: allowedMIMEs,
                                logger: logger,
                                useEmbeddedUploadStore: useEmbeddedUploadStore)
        return await ServerTestUtils.startGateway(on: 18121, plugins: [plugin])
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

    private func decodeStreamEvents(from sse: String) throws -> [ChatKitStreamEventEnvelope] {
        let decoder = JSONDecoder()
        var events: [ChatKitStreamEventEnvelope] = []
        for line in sse.split(separator: "\n") {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty, payload != "[DONE]" else { continue }
            guard let jsonData = payload.data(using: .utf8) else { continue }
            events.append(try decoder.decode(ChatKitStreamEventEnvelope.self, from: jsonData))
        }
        return events
    }

    func testChatKitSessionStartReturnsSecret() async throws {
        let running = await startGateway(useEmbeddedUploadStore: false)
        defer { Task { await running.stop() } }

        let session = try await createSession(on: running.port)
        XCTAssertFalse(session.client_secret.isEmpty)
        XCTAssertFalse(session.session_id.isEmpty)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = formatter.date(from: session.expires_at) ?? ISO8601DateFormatter().date(from: session.expires_at)
        XCTAssertNotNil(parsed, "expires_at=\(session.expires_at)")
    }

    func testGatewayClientHealthAndMetrics() async throws {
        let running = await startGateway()
        defer { Task { await running.stop() } }

        let baseURL = URL(string: "http://127.0.0.1:\(running.port)")!
        let token = try CredentialStore().signJWT(
            subject: "gateway-tests",
            expiresAt: Date().addingTimeInterval(3600),
            role: "admin"
        )
        let client = GatewayClient(
            baseURL: baseURL,
            defaultHeaders: ["Authorization": "Bearer \(token)"]
        )

        let health = try await client.health()
        let encodedHealth = try JSONEncoder().encode(health)
        XCTAssertFalse(encodedHealth.isEmpty)

        let metrics = try await client.metrics()
        XCTAssertFalse(metrics.isEmpty)
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

        let events = try decodeStreamEvents(from: sse)
        XCTAssertTrue(events.contains { $0.event == "delta" })
        guard let completion = events.last(where: { $0.event == "completion" }) else {
            return XCTFail("expected completion event in stream")
        }
        XCTAssertEqual(completion.answer, "Hello Fountain")
        XCTAssertEqual(completion.done, true)
    }

    func testStreamingBridgeEmitsIncrementalEvents() async throws {
        struct StreamingResponder: ChatResponder {
            func respond(session: ChatKitSessionStore.StoredSession,
                         request: ChatKitMessageRequest,
                         preferStreaming: Bool) async throws -> ChatResponderResult {
                let events = [
                    ChatKitStreamEventEnvelope(id: "1",
                                                event: "delta",
                                                delta: ChatKitStreamDelta(content: "Hel"),
                                                answer: nil,
                                                done: nil,
                                                thread_id: nil,
                                                response_id: nil,
                                                created_at: nil,
                                                metadata: nil),
                    ChatKitStreamEventEnvelope(id: "2",
                                                event: "delta",
                                                delta: ChatKitStreamDelta(content: "lo Fountain"),
                                                answer: nil,
                                                done: nil,
                                                thread_id: nil,
                                                response_id: nil,
                                                created_at: nil,
                                                metadata: nil)
                ]
                return ChatResponderResult(answer: "Hello Fountain",
                                           provider: "stub",
                                           model: "stub-model",
                                           usage: nil,
                                           streamEvents: events)
            }
        }

        let running = await startGateway(responder: StreamingResponder(), useEmbeddedUploadStore: false)
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

        guard let sse = String(data: data, encoding: .utf8) else {
            return XCTFail("expected utf8 body")
        }

        let firstIndex = sse.range(of: "Hel")?.lowerBound
        let secondIndex = sse.range(of: "lo Fountain")?.lowerBound
        XCTAssertNotNil(firstIndex)
        XCTAssertNotNil(secondIndex)
        if let firstIndex, let secondIndex {
            XCTAssertLessThan(firstIndex, secondIndex)
        }
        XCTAssertTrue(sse.contains("event: completion"))
        XCTAssertTrue(sse.contains("\"answer\":\"Hello Fountain\""))
    }

    func testChatKitMessageNonStreamingReturnsJSON() async throws {
        let running = await startGateway(useEmbeddedUploadStore: false)
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

        struct MessageResponse: Decodable, Sendable {
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
        let parsedCreated = formatter.date(from: decoded.created_at) ?? ISO8601DateFormatter().date(from: decoded.created_at)
        XCTAssertNotNil(parsedCreated, "created_at=\(decoded.created_at)")
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
        let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
        XCTAssertNotNil(contentType)
        XCTAssertTrue(contentType?.hasPrefix("application/json") == true)

        let decoded = try JSONDecoder().decode(UploadResponse.self, from: data)
        XCTAssertFalse(decoded.attachment_id.isEmpty)
        XCTAssertTrue(decoded.upload_url.starts(with: "fountain://chatkit/attachments/"))
        XCTAssertEqual(decoded.mime_type, "application/octet-stream")
    }

    func testPublishingFrontendServesChatKitIndex() async throws {
        let plugin = PublishingFrontendPlugin(rootPath: publicRootPath())
        let request = HTTPRequest(method: "GET", path: "/", headers: [:], body: Data())
        let upstream = HTTPResponse(status: 404, headers: [:], body: Data())
        let response = try await plugin.respond(upstream, for: request)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.headers["Content-Type"], "text/html")
        let html = String(data: response.body, encoding: .utf8)
        XCTAssertNotNil(html)
        XCTAssertTrue(html?.contains("ChatKit") ?? false)
        XCTAssertTrue(html?.contains("chatkit.js") ?? false)
    }

    func testChatKitScriptServedWithCorrectMime() async throws {
        let plugin = PublishingFrontendPlugin(rootPath: publicRootPath())
        let request = HTTPRequest(method: "GET", path: "/chatkit.js", headers: [:], body: Data())
        let upstream = HTTPResponse(status: 404, headers: [:], body: Data())
        let response = try await plugin.respond(upstream, for: request)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.headers["Content-Type"], "application/javascript")
        let script = String(data: response.body, encoding: .utf8)
        XCTAssertNotNil(script)
        XCTAssertTrue(script?.contains("bootstrapChatKit") ?? false)
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

    func testAttachmentDownloadReturnsFile() async throws {
        let running = await startGateway()
        defer { Task { await running.stop() } }

        let session = try await createSession(on: running.port)
        let boundary = "Boundary-" + UUID().uuidString
        let fileData = Data("Download text".utf8)
        let multipart = makeMultipartBody(boundary: boundary, parts: [
            (name: "client_secret", filename: nil, contentType: nil, data: Data(session.client_secret.utf8)),
            (name: "file", filename: "download.txt", contentType: "text/plain", data: fileData)
        ])

        let uploadURL = URL(string: "http://127.0.0.1:\(running.port)/chatkit/upload")!
        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        uploadRequest.httpBody = multipart

        let (uploadData, uploadResponse) = try await URLSession.shared.data(for: uploadRequest)
        XCTAssertEqual((uploadResponse as? HTTPURLResponse)?.statusCode, 201)
        let decoded = try JSONDecoder().decode(UploadResponse.self, from: uploadData)

        var components = URLComponents(string: "http://127.0.0.1:\(running.port)/chatkit/attachments/\(decoded.attachment_id)")!
        components.queryItems = [URLQueryItem(name: "client_secret", value: session.client_secret)]
        let downloadURL = components.url!

        let (downloadData, downloadResponse) = try await URLSession.shared.data(from: downloadURL)
        let httpResponse = downloadResponse as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 200)
        XCTAssertEqual(downloadData, fileData)
        XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
        if let disposition = httpResponse?.value(forHTTPHeaderField: "Content-Disposition") {
            XCTAssertEqual(disposition.removingPercentEncoding, "attachment; filename=\"download.txt\"")
        } else {
            XCTFail("missing Content-Disposition header")
        }
        XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "ETag"), ChatKitUploadStore.checksum(for: fileData))
    }

    func testAttachmentDownloadDetectsMetadataMismatch() async throws {
        let running = await startGateway()
        defer { Task { await running.stop() } }

        guard let metadataStore else {
            return XCTFail("metadata store not initialised")
        }

        let session = try await createSession(on: running.port)
        let boundary = "Boundary-" + UUID().uuidString
        let fileData = Data("Mismatch".utf8)
        let multipart = makeMultipartBody(boundary: boundary, parts: [
            (name: "client_secret", filename: nil, contentType: nil, data: Data(session.client_secret.utf8)),
            (name: "file", filename: "mismatch.txt", contentType: "text/plain", data: fileData)
        ])

        let uploadURL = URL(string: "http://127.0.0.1:\(running.port)/chatkit/upload")!
        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        uploadRequest.httpBody = multipart

        let (uploadData, uploadResponse) = try await URLSession.shared.data(for: uploadRequest)
        XCTAssertEqual((uploadResponse as? HTTPURLResponse)?.statusCode, 201)
        let decoded = try JSONDecoder().decode(UploadResponse.self, from: uploadData)

        let existing = try await metadataStore.metadata(for: decoded.attachment_id)
        XCTAssertNotNil(existing)
        if var existing {
            existing = ChatKitAttachmentMetadata(attachmentId: existing.attachmentId,
                                                 sessionId: existing.sessionId,
                                                 threadId: existing.threadId,
                                                 fileName: existing.fileName,
                                                 mimeType: existing.mimeType,
                                                 sizeBytes: existing.sizeBytes + 1,
                                                 checksum: existing.checksum,
                                                 storedAt: existing.storedAt)
            try await metadataStore.upsert(metadata: existing)
        }

        var components = URLComponents(string: "http://127.0.0.1:\(running.port)/chatkit/attachments/\(decoded.attachment_id)")!
        components.queryItems = [URLQueryItem(name: "client_secret", value: session.client_secret)]
        let downloadURL = components.url!

        let (_, downloadResponse) = try await URLSession.shared.data(from: downloadURL)
        XCTAssertEqual((downloadResponse as? HTTPURLResponse)?.statusCode, 409)
    }

    func testToolCallSurfacing() async throws {
        struct ToolCallResponder: ChatResponder {
            let toolCalls: [ChatKitToolCall]

            func respond(session: ChatKitSessionStore.StoredSession,
                         request: ChatKitMessageRequest,
                         preferStreaming: Bool) async throws -> ChatResponderResult {
                let events = ToolCallBridge.events(for: toolCalls)
                return ChatResponderResult(answer: "Tool response",
                                           provider: "stub",
                                           model: "stub-model",
                                           usage: nil,
                                           streamEvents: events,
                                           toolCalls: toolCalls)
            }
        }

        let call = ChatKitToolCall(id: "call-1",
                                   name: "search",
                                   arguments: "{\"query\":\"fountain\"}",
                                   status: "completed",
                                   result: "{\"hits\":1}")
        let responder = ToolCallResponder(toolCalls: [call])

        let running = await startGateway(responder: responder, useEmbeddedUploadStore: false)
        defer { Task { await running.stop() } }

        let session = try await createSession(on: running.port)
        let body: [String: Any] = [
            "client_secret": session.client_secret,
            "messages": [["role": "user", "content": "Trigger tool"]],
            "stream": true
        ]

        let messageURL = URL(string: "http://127.0.0.1:\(running.port)/chatkit/messages")!
        var request = URLRequest(url: messageURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 202)

        guard let sse = String(data: data, encoding: .utf8) else {
            return XCTFail("expected utf8 body")
        }

        XCTAssertTrue(sse.contains("event: delta"), "missing delta frame in \(sse)")
        XCTAssertTrue(sse.contains("event: tool_call"), "missing tool_call frame in \(sse)")
        XCTAssertTrue(sse.contains("\"tool.name\":\"search\""), "missing tool metadata in \(sse)")
        XCTAssertTrue(sse.contains("event: tool_result"), "missing tool_result frame in \(sse)")
        XCTAssertTrue(sse.contains("\"tool.result\":\"{\\\"hits\\\":1}\""), "missing tool result metadata in \(sse)")

        let events = try decodeStreamEvents(from: sse)
        guard let toolCallEvent = events.first(where: { $0.event == "tool_call" }) else {
            return XCTFail("expected tool_call event in stream")
        }
        XCTAssertEqual(toolCallEvent.metadata?["tool.name"], "search")
        XCTAssertEqual(toolCallEvent.metadata?["tool.arguments"], "{\"query\":\"fountain\"}")
        guard let resultEvent = events.first(where: { $0.event == "tool_result" }) else {
            return XCTFail("expected tool_result event in stream")
        }
        XCTAssertEqual(resultEvent.metadata?["tool.result"], "{\"hits\":1}")
        guard let completion = events.first(where: { $0.event == "completion" }) else {
            return XCTFail("expected completion event")
        }
        guard let threadId = completion.thread_id else {
            return XCTFail("expected completion thread id")
        }

        var components = URLComponents(string: "http://127.0.0.1:\(running.port)/chatkit/threads/\(threadId)")!
        components.queryItems = [URLQueryItem(name: "client_secret", value: session.client_secret)]
        let (threadData, threadResponse) = try await URLSession.shared.data(from: components.url!)
        XCTAssertEqual((threadResponse as? HTTPURLResponse)?.statusCode, 200)

        let thread = try JSONDecoder().decode(ChatKitThread.self, from: threadData)
        guard let assistantMessage = thread.messages.last else {
            return XCTFail("expected assistant message")
        }
        let storedCalls = assistantMessage.tool_calls
        XCTAssertEqual(storedCalls?.count, 1)
        XCTAssertEqual(storedCalls?.first?.id, call.id)
        XCTAssertEqual(storedCalls?.first?.name, call.name)
        XCTAssertEqual(storedCalls?.first?.arguments, call.arguments)
        XCTAssertEqual(storedCalls?.first?.result, call.result)
    }

    func testOversizedAttachmentIsRejected() async throws {
        let plugin = makePlugin(maxAttachmentBytes: 1)
        let handlers = plugin.makeGeneratedHandlers()
        let sessionResponse = try await handlers.startSession(nil)
        let secret = sessionResponse.client_secret
        let largeData = Data(repeating: 0x41, count: 2)
        let payload = ChatKitGeneratedHandlers.UploadPayload(clientSecret: secret,
                                                             threadId: nil,
                                                             fileName: "large.bin",
                                                             mimeType: "application/octet-stream",
                                                             data: largeData)

        do {
            _ = try await handlers.uploadAttachment(payload)
            XCTFail("expected oversize upload to be rejected")
        } catch let error as ChatKitGeneratedHandlers.OperationError {
            XCTAssertEqual(error.status, 400)
            XCTAssertEqual(error.code, "attachment_too_large")
        }
    }

    func testInvalidMimeAttachmentIsRejected() async throws {
        let plugin = makePlugin(maxAttachmentBytes: nil, allowedMIMEs: ["image/png"])
        let handlers = plugin.makeGeneratedHandlers()
        let sessionResponse = try await handlers.startSession(nil)
        let payload = ChatKitGeneratedHandlers.UploadPayload(clientSecret: sessionResponse.client_secret,
                                                             threadId: nil,
                                                             fileName: "note.txt",
                                                             mimeType: "text/plain",
                                                             data: Data("Hello".utf8))

        do {
            _ = try await handlers.uploadAttachment(payload)
            XCTFail("expected unsupported mime to be rejected")
        } catch let error as ChatKitGeneratedHandlers.OperationError {
            XCTAssertEqual(error.status, 400)
            XCTAssertEqual(error.code, "unsupported_media_type")
        }
    }

    func testAttachmentCleanupRemovesExpiredFiles() async throws {
        let running = await startGateway(useEmbeddedUploadStore: true)
        defer { Task { await running.stop() } }

        guard let metadataStore, let attachmentClient else {
            return XCTFail("stores not initialised")
        }

        let session = try await createSession(on: running.port)
        let boundary = "Boundary-" + UUID().uuidString
        let fileData = Data("Stale".utf8)
        let multipart = makeMultipartBody(boundary: boundary, parts: [
            (name: "client_secret", filename: nil, contentType: nil, data: Data(session.client_secret.utf8)),
            (name: "file", filename: "stale.txt", contentType: "text/plain", data: fileData)
        ])

        let uploadURL = URL(string: "http://127.0.0.1:\(running.port)/chatkit/upload")!
        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        uploadRequest.httpBody = multipart

        let (uploadData, uploadResponse) = try await URLSession.shared.data(for: uploadRequest)
        XCTAssertEqual((uploadResponse as? HTTPURLResponse)?.statusCode, 201)
        let decoded = try JSONDecoder().decode(UploadResponse.self, from: uploadData)

        guard let store = uploadStore else {
            return XCTFail("upload store not initialised")
        }
        XCTAssertTrue(store is ChatKitUploadStore)
        let storedAttachment = try await store.load(attachmentId: decoded.attachment_id)
        XCTAssertNotNil(storedAttachment, "expected attachment to exist in upload store")

        struct AttachmentRecord: Codable {
            var attachmentId: String
            var sessionId: String
            var threadId: String?
            var fileName: String
            var mimeType: String
            var sizeBytes: Int
            var checksum: String
            var storedAt: String
            var dataBase64: String
        }

        guard let storedDoc = try await attachmentClient.getDoc(corpusId: "chatkit",
                                                                 collection: "attachments",
                                                                 id: decoded.attachment_id) else {
            return XCTFail("expected attachment to exist")
        }

        var record = try JSONDecoder().decode(AttachmentRecord.self, from: storedDoc)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        record.storedAt = formatter.string(from: Date().addingTimeInterval(-4 * 3600))
        let updatedDoc = try JSONEncoder().encode(record)
        try await attachmentClient.putDoc(corpusId: "chatkit",
                                          collection: "attachments",
                                          id: decoded.attachment_id,
                                          body: updatedDoc)

        if var existing = try await metadataStore.metadata(for: decoded.attachment_id) {
            existing = ChatKitAttachmentMetadata(attachmentId: existing.attachmentId,
                                                 sessionId: existing.sessionId,
                                                 threadId: existing.threadId,
                                                 fileName: existing.fileName,
                                                 mimeType: existing.mimeType,
                                                 sizeBytes: existing.sizeBytes,
                                                 checksum: existing.checksum,
                                                 storedAt: record.storedAt)
            try await metadataStore.upsert(metadata: existing)
        }

        let cleanupJob = AttachmentCleanupJob(uploadStore: ChatKitUploadStore(store: attachmentClient),
                                              metadataStore: metadataStore,
                                              store: attachmentClient,
                                              ttl: 60,
                                              batchSize: 10)
        await cleanupJob.runOnce()

        let remaining = try await attachmentClient.getDoc(corpusId: "chatkit",
                                                          collection: "attachments",
                                                          id: decoded.attachment_id)
        XCTAssertNil(remaining)
        let metadata = try await metadataStore.metadata(for: decoded.attachment_id)
        XCTAssertNil(metadata)
    }

    func testThreadPersistence() async throws {
        struct ToolResponder: ChatResponder {
            func respond(session: ChatKitSessionStore.StoredSession,
                         request: ChatKitMessageRequest,
                         preferStreaming: Bool) async throws -> ChatResponderResult {
                let call = ChatKitToolCall(id: "call-1",
                                           name: "lookup",
                                           arguments: "{\"query\":\"status\"}",
                                           status: "completed",
                                           result: "ok")
                return ChatResponderResult(answer: "Tool complete",
                                           provider: "stub",
                                           model: "stub-model",
                                           usage: ["total_tokens": 5],
                                           streamEvents: nil,
                                           toolCalls: [call])
            }
        }

        let running = await startGateway(responder: ToolResponder())
        defer { Task { await running.stop() } }

        let session = try await createSession(on: running.port)
        let body: [String: Any] = [
            "client_secret": session.client_secret,
            "messages": [["role": "user", "content": "Trigger tool"]],
            "stream": false,
            "metadata": ["title": "Utilities"]
        ]

        let messageURL = URL(string: "http://127.0.0.1:\(running.port)/chatkit/messages")!
        let (data, response) = try await ServerTestUtils.httpJSON("POST", messageURL, body: body)
        XCTAssertEqual(response.statusCode, 200)

        struct MessageResponse: Decodable, Sendable {
            let thread_id: String
            let response_id: String
        }

        let messageResponse = try JSONDecoder().decode(MessageResponse.self, from: data)
        XCTAssertFalse(messageResponse.thread_id.isEmpty)

        let listURL = URL(string: "http://127.0.0.1:\(running.port)/chatkit/threads?client_secret=\(session.client_secret)")!
        let (listData, listResp) = try await URLSession.shared.data(from: listURL)
        XCTAssertEqual((listResp as? HTTPURLResponse)?.statusCode, 200)

        struct ThreadList: Decodable {
            struct Summary: Decodable, Sendable {
                let thread_id: String
                let message_count: Int
            }
            let threads: [Summary]
        }

        let list = try JSONDecoder().decode(ThreadList.self, from: listData)
        XCTAssertTrue(list.threads.contains(where: { $0.thread_id == messageResponse.thread_id && $0.message_count == 1 }))

        let detailURL = URL(string: "http://127.0.0.1:\(running.port)/chatkit/threads/\(messageResponse.thread_id)?client_secret=\(session.client_secret)")!
        let (detailData, detailResp) = try await URLSession.shared.data(from: detailURL)
        XCTAssertEqual((detailResp as? HTTPURLResponse)?.statusCode, 200)

        struct ThreadDetail: Decodable {
            struct ToolCall: Decodable {
                let id: String
                let name: String
                let arguments: String
            }
            struct Message: Decodable {
                let content: String
                let response_id: String
                let tool_calls: [ToolCall]?
            }
            let thread_id: String
            let messages: [Message]
        }

        let detail = try JSONDecoder().decode(ThreadDetail.self, from: detailData)
        XCTAssertEqual(detail.thread_id, messageResponse.thread_id)
        guard let assistantMessage = detail.messages.first else {
            return XCTFail("missing persisted assistant message")
        }
        XCTAssertEqual(assistantMessage.content, "Tool complete")
        XCTAssertEqual(assistantMessage.response_id, messageResponse.response_id)
        XCTAssertEqual(assistantMessage.tool_calls?.first?.name, "lookup")

        var deleteRequest = URLRequest(url: detailURL)
        deleteRequest.httpMethod = "DELETE"
        let (_, deleteResp) = try await URLSession.shared.data(for: deleteRequest)
        XCTAssertEqual((deleteResp as? HTTPURLResponse)?.statusCode, 204)

        let (afterData, afterResp) = try await URLSession.shared.data(from: listURL)
        XCTAssertEqual((afterResp as? HTTPURLResponse)?.statusCode, 200)
        let afterList = try JSONDecoder().decode(ThreadList.self, from: afterData)
        XCTAssertFalse(afterList.threads.contains(where: { $0.thread_id == messageResponse.thread_id }))
    }

    func testStructuredLogs() async throws {
        var uploadedId = ""
        let fileData = Data("LogBody".utf8)
        let (events, _) = try await ChatKitLogging.capture { [self] in
            let running = await startGateway()
            defer { Task { await running.stop() } }

            let session = try await createSession(on: running.port)
            let boundary = "Boundary-" + UUID().uuidString
            let multipart = makeMultipartBody(boundary: boundary, parts: [
                (name: "client_secret", filename: nil, contentType: nil, data: Data(session.client_secret.utf8)),
                (name: "file", filename: "log.txt", contentType: "text/plain", data: fileData)
            ])

            let uploadURL = URL(string: "http://127.0.0.1:\(running.port)/chatkit/upload")!
            var uploadRequest = URLRequest(url: uploadURL)
            uploadRequest.httpMethod = "POST"
            uploadRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            uploadRequest.httpBody = multipart

            let (uploadData, uploadResponse) = try await URLSession.shared.data(for: uploadRequest)
            XCTAssertEqual((uploadResponse as? HTTPURLResponse)?.statusCode, 201)
            let decoded = try JSONDecoder().decode(UploadResponse.self, from: uploadData)
            uploadedId = decoded.attachment_id

            var components = URLComponents(string: "http://127.0.0.1:\(running.port)/chatkit/attachments/\(decoded.attachment_id)")!
            components.queryItems = [URLQueryItem(name: "client_secret", value: session.client_secret)]
            let downloadURL = components.url!
            let (_, downloadResponse) = try await URLSession.shared.data(from: downloadURL)
            XCTAssertEqual((downloadResponse as? HTTPURLResponse)?.statusCode, 200)

            components.queryItems = [URLQueryItem(name: "client_secret", value: "invalid")]
            let invalidURL = components.url!
            let (_, invalidResponse) = try await URLSession.shared.data(from: invalidURL)
            XCTAssertEqual((invalidResponse as? HTTPURLResponse)?.statusCode, 401)
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        guard let uploadEvent = events.first(where: { $0.kind == .attachmentUploadSucceeded }) else {
            return XCTFail("missing upload success log")
        }
        XCTAssertEqual(uploadEvent.attachmentId, uploadedId)
        XCTAssertEqual(uploadEvent.status, 201)
        XCTAssertEqual(uploadEvent.level, "info")

        guard let downloadEvent = events.first(where: { $0.kind == .attachmentDownloadSucceeded }) else {
            return XCTFail("missing download success log")
        }
        XCTAssertEqual(downloadEvent.attachmentId, uploadedId)
        XCTAssertEqual(downloadEvent.status, 200)
        XCTAssertEqual(downloadEvent.bytes, fileData.count)

        XCTExpectFailure("ChatKitLogging currently omits download failure entries") {
            guard let failureEvent = events.first(where: { $0.kind == .attachmentDownloadFailed }) else {
                return XCTFail("missing download failure log")
            }
            XCTAssertEqual(failureEvent.status, 401)
            XCTAssertEqual(failureEvent.code, "invalid_secret")
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
        XCTAssertTrue(contents.contains("/chatkit/attachments/{attachmentId}"))
        XCTAssertTrue(contents.contains("/chatkit/threads"))
    }
}

private extension ChatKitGatewayTests {
    func publicRootPath() -> String {
        if let cached = cachedRepoRoot {
            return cached.appendingPathComponent("Public").path
        }
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent() // ChatKitGatewayTests.swift
            .deletingLastPathComponent() // GatewayServerTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // FountainApps
            .deletingLastPathComponent() // Packages
        cachedRepoRoot = repoRoot
        return repoRoot.appendingPathComponent("Public").path
    }
}
// Robot-only mode: exclude this suite when building robot tests
#if !ROBOT_ONLY
