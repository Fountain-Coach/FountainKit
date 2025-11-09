import Foundation
import OpenAPIRuntime
import gateway_service
import HTTPTypes
import FountainRuntime
#if canImport(ChatKitGatewayPlugin)
import ChatKitGatewayPlugin
#endif

// Generated handlers bridge to GatewayServer logic.
public struct GatewayOpenAPI: APIProtocol, @unchecked Sendable {
    let host: GatewayServer
    public init(host: GatewayServer) { self.host = host }

    public func gatewayHealth(_ input: Operations.gatewayHealth.Input) async throws -> Operations.gatewayHealth.Output {
        // Host returns a JSON object; respond with an empty object container.
        if let container = try? OpenAPIRuntime.OpenAPIObjectContainer(unvalidatedValue: [:]) {
            return .ok(.init(body: .json(container)))
        }
        return .undocumented(statusCode: 500, OpenAPIRuntime.UndocumentedPayload())
    }

    public func gatewayMetrics(_ input: Operations.gatewayMetrics.Input) async throws -> Operations.gatewayMetrics.Output {
        let resp = await host.gatewayMetrics()
        if let body = try? JSONDecoder().decode(Operations.gatewayMetrics.Output.Ok.Body.jsonPayload.self, from: resp.body) {
            return .ok(.init(body: .json(body)))
        }
        return .undocumented(statusCode: resp.status, OpenAPIRuntime.UndocumentedPayload())
    }

    public func issueAuthToken(_ input: Operations.issueAuthToken.Input) async throws -> Operations.issueAuthToken.Output {
        guard case let .json(req) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        // Reuse existing host logic by constructing an HTTPRequest
        let cred: [String: String] = ["clientId": req.clientId, "clientSecret": req.clientSecret]
        let data = try JSONSerialization.data(withJSONObject: cred)
        let httpReq = HTTPRequest(method: "POST", path: "/auth/token", headers: ["Content-Type": "application/json"], body: data)
        let resp = await host.issueAuthToken(httpReq)
        if resp.status == 200 {
            // Decode using ISO8601 strategy to match OpenAPI date-time
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            if let tok = try? dec.decode(Components.Schemas.TokenResponse.self, from: resp.body) {
                return .ok(.init(body: .json(tok)))
            }
            // Fallback: parse string date then construct typed response
            if let obj = try? JSONSerialization.jsonObject(with: resp.body) as? [String: Any],
               let token = obj["token"] as? String,
               let expires = obj["expiresAt"] as? String,
               let date = ISO8601DateFormatter().date(from: expires) {
                let tok = Components.Schemas.TokenResponse(token: token, expiresAt: date)
                return .ok(.init(body: .json(tok)))
            }
        } else if resp.status == 401, let err = try? JSONDecoder().decode(Components.Schemas.ErrorResponse.self, from: resp.body) {
            return .unauthorized(.init(body: .json(err)))
        }
        return .undocumented(statusCode: resp.status, OpenAPIRuntime.UndocumentedPayload())
    }

    public func certificateInfo(_ input: Operations.certificateInfo.Input) async throws -> Operations.certificateInfo.Output {
        let resp = await host.certificateInfo()
        if resp.status == 200, let info = try? JSONDecoder().decode(Components.Schemas.CertificateInfo.self, from: resp.body) {
            return .ok(.init(body: .json(info)))
        }
        return .undocumented(statusCode: resp.status, OpenAPIRuntime.UndocumentedPayload())
    }

    public func renewCertificate(_ input: Operations.renewCertificate.Input) async throws -> Operations.renewCertificate.Output {
        let resp = await host.renewCertificate()
        if resp.status == 202, let container = try? OpenAPIRuntime.OpenAPIObjectContainer(unvalidatedValue: ["status": "triggered"]) {
            return .accepted(.init(body: .json(container)))
        }
        return .undocumented(statusCode: resp.status, OpenAPIRuntime.UndocumentedPayload())
    }

    public func startChatKitSession(_ input: Operations.startChatKitSession.Input) async throws -> Operations.startChatKitSession.Output {
        guard let handlers = await host.chatKitGeneratedHandlers() else {
            return .undocumented(statusCode: 501, unavailablePayload())
        }

        let requestModel: ChatKitSessionRequest?
        if let body = input.body {
            switch body {
            case .json(let payload):
                requestModel = ChatKitSessionRequest(
                    persona: payload.persona,
                    userId: payload.userId,
                    metadata: payload.metadata?.additionalProperties
                )
            }
        } else {
            requestModel = nil
        }

        do {
            let session = try await handlers.startSession(requestModel)
            let response = try convertSessionResponse(session)
            return .created(.init(body: .json(response)))
        } catch let error as ChatKitGeneratedHandlers.OperationError {
            switch error.status {
            case 400:
                return .badRequest(.init(body: .json(makeErrorBody(error))))
            default:
                return .undocumented(statusCode: error.status, undocumentedPayload(status: error.status, error: error))
            }
        }
    }

    public func refreshChatKitSession(_ input: Operations.refreshChatKitSession.Input) async throws -> Operations.refreshChatKitSession.Output {
        guard let handlers = await host.chatKitGeneratedHandlers() else {
            return .undocumented(statusCode: 501, unavailablePayload())
        }

        let requestModel: ChatKitSessionRefreshRequest
        switch input.body {
        case .json(let payload):
            requestModel = ChatKitSessionRefreshRequest(client_secret: payload.client_secret)
        }

        do {
            let session = try await handlers.refreshSession(requestModel)
            let response = try convertSessionResponse(session)
            return .ok(.init(body: .json(response)))
        } catch let error as ChatKitGeneratedHandlers.OperationError {
            switch error.status {
            case 400:
                return .badRequest(.init(body: .json(makeErrorBody(error))))
            case 401:
                return .unauthorized(.init(body: .json(makeErrorBody(error))))
            default:
                return .undocumented(statusCode: error.status, undocumentedPayload(status: error.status, error: error))
            }
        }
    }

    public func postChatKitMessage(_ input: Operations.postChatKitMessage.Input) async throws -> Operations.postChatKitMessage.Output {
        guard let handlers = await host.chatKitGeneratedHandlers() else {
            return .undocumented(statusCode: 501, unavailablePayload())
        }

        let requestModel: ChatKitMessageRequest
        switch input.body {
        case .json(let payload):
            requestModel = try convertMessageRequest(payload)
        }

        do {
            let result = try await handlers.postMessage(requestModel)
            switch result.body {
            case .json(let payload):
                let converted = try convertMessageResponse(payload)
                return .ok(.init(body: .json(converted)))
            case .stream(let data, _):
                return .accepted(.init(body: .text_event_hyphen_stream(OpenAPIRuntime.HTTPBody(data))))
            }
        } catch let error as ChatKitGeneratedHandlers.OperationError {
            switch error.status {
            case 400:
                return .badRequest(.init(body: .json(makeErrorBody(error))))
            case 401:
                return .unauthorized(.init(body: .json(makeErrorBody(error))))
            default:
                return .undocumented(statusCode: error.status, undocumentedPayload(status: error.status, error: error))
            }
        }
    }

    public func uploadChatKitAttachment(_ input: Operations.uploadChatKitAttachment.Input) async throws -> Operations.uploadChatKitAttachment.Output {
        guard let handlers = await host.chatKitGeneratedHandlers() else {
            return .undocumented(statusCode: 501, unavailablePayload())
        }

        let payload = try await parseUploadPayload(input.body)

        do {
            let response = try await handlers.uploadAttachment(payload)
            let converted = convertUploadResponse(response)
            return .created(.init(body: .json(converted)))
        } catch let error as ChatKitGeneratedHandlers.OperationError {
            switch error.status {
            case 400:
                return .badRequest(.init(body: .json(makeErrorBody(error))))
            case 401:
                return .unauthorized(.init(body: .json(makeErrorBody(error))))
            default:
                return .undocumented(statusCode: error.status, undocumentedPayload(status: error.status, error: error))
            }
        }
    }

    public func downloadChatKitAttachment(_ input: Operations.downloadChatKitAttachment.Input) async throws -> Operations.downloadChatKitAttachment.Output {
        guard let handlers = await host.chatKitGeneratedHandlers() else {
            return .undocumented(statusCode: 501, unavailablePayload())
        }

        do {
            let result = try await handlers.downloadAttachment(clientSecret: input.query.client_secret, attachmentId: input.path.attachmentId)
            let okHeaders = Operations.downloadChatKitAttachment.Output.Ok.Headers(
                Cache_hyphen_Control: result.headers["Cache-Control"],
                Content_hyphen_Disposition: result.headers["Content-Disposition"],
                ETag: result.headers["ETag"]
            )
            return .ok(.init(headers: okHeaders, body: .binary(OpenAPIRuntime.HTTPBody(result.data))))
        } catch let error as ChatKitGeneratedHandlers.OperationError {
            switch error.status {
            case 400:
                return .badRequest(.init(body: .json(makeErrorBody(error))))
            case 401:
                return .unauthorized(.init(body: .json(makeErrorBody(error))))
            case 403:
                return .forbidden(.init(body: .json(makeErrorBody(error))))
            case 404:
                return .notFound(.init(body: .json(makeErrorBody(error))))
            case 409:
                return .conflict(.init(body: .json(makeErrorBody(error))))
            default:
                return .undocumented(statusCode: error.status, undocumentedPayload(status: error.status, error: error))
            }
        }
    }

    public func listChatKitThreads(_ input: Operations.listChatKitThreads.Input) async throws -> Operations.listChatKitThreads.Output {
        guard let handlers = await host.chatKitGeneratedHandlers() else {
            return .undocumented(statusCode: 501, unavailablePayload())
        }

        do {
            let threads = try await handlers.listThreads(clientSecret: input.query.client_secret)
            let converted = try convertThreadListResponse(threads)
            return .ok(.init(body: .json(converted)))
        } catch let error as ChatKitGeneratedHandlers.OperationError {
            switch error.status {
            case 400:
                return .badRequest(.init(body: .json(makeErrorBody(error))))
            case 401:
                return .unauthorized(.init(body: .json(makeErrorBody(error))))
            default:
                return .undocumented(statusCode: error.status, undocumentedPayload(status: error.status, error: error))
            }
        }
    }

    public func createChatKitThread(_ input: Operations.createChatKitThread.Input) async throws -> Operations.createChatKitThread.Output {
        guard let handlers = await host.chatKitGeneratedHandlers() else {
            return .undocumented(statusCode: 501, unavailablePayload())
        }

        let requestModel: ChatKitThreadCreateRequest
        switch input.body {
        case .json(let payload):
            requestModel = ChatKitThreadCreateRequest(
                client_secret: payload.client_secret,
                title: payload.title,
                metadata: payload.metadata?.additionalProperties
            )
        }

        do {
            let thread = try await handlers.createThread(requestModel)
            let converted = try convertThread(thread)
            return .created(.init(body: .json(converted)))
        } catch let error as ChatKitGeneratedHandlers.OperationError {
            switch error.status {
            case 400:
                return .badRequest(.init(body: .json(makeErrorBody(error))))
            case 401:
                return .unauthorized(.init(body: .json(makeErrorBody(error))))
            default:
                return .undocumented(statusCode: error.status, undocumentedPayload(status: error.status, error: error))
            }
        }
    }

    public func getChatKitThread(_ input: Operations.getChatKitThread.Input) async throws -> Operations.getChatKitThread.Output {
        guard let handlers = await host.chatKitGeneratedHandlers() else {
            return .undocumented(statusCode: 501, unavailablePayload())
        }

        do {
            let thread = try await handlers.getThread(clientSecret: input.query.client_secret, threadId: input.path.threadId)
            let converted = try convertThread(thread)
            return .ok(.init(body: .json(converted)))
        } catch let error as ChatKitGeneratedHandlers.OperationError {
            switch error.status {
            case 400:
                return .badRequest(.init(body: .json(makeErrorBody(error))))
            case 401:
                return .unauthorized(.init(body: .json(makeErrorBody(error))))
            case 404:
                return .notFound(.init(body: .json(makeErrorBody(error))))
            default:
                return .undocumented(statusCode: error.status, undocumentedPayload(status: error.status, error: error))
            }
        }
    }

    public func deleteChatKitThread(_ input: Operations.deleteChatKitThread.Input) async throws -> Operations.deleteChatKitThread.Output {
        guard let handlers = await host.chatKitGeneratedHandlers() else {
            return .undocumented(statusCode: 501, unavailablePayload())
        }

        do {
            try await handlers.deleteThread(clientSecret: input.query.client_secret, threadId: input.path.threadId)
            return .noContent(.init())
        } catch let error as ChatKitGeneratedHandlers.OperationError {
            switch error.status {
            case 400:
                return .badRequest(.init(body: .json(makeErrorBody(error))))
            case 401:
                return .unauthorized(.init(body: .json(makeErrorBody(error))))
            case 404:
                return .notFound(.init(body: .json(makeErrorBody(error))))
            default:
                return .undocumented(statusCode: error.status, undocumentedPayload(status: error.status, error: error))
            }
        }
    }
    public func listRoutes(_ input: Operations.listRoutes.Input) async throws -> Operations.listRoutes.Output {
        let resp = await host.listRoutes()
        if resp.status == 200, let routes = try? JSONDecoder().decode([Components.Schemas.RouteInfo].self, from: resp.body) {
            return .ok(.init(body: .json(routes)))
        }
        return .undocumented(statusCode: resp.status, OpenAPIRuntime.UndocumentedPayload())
    }

    public func createRoute(_ input: Operations.createRoute.Input) async throws -> Operations.createRoute.Output {
        guard case let .json(route) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let data = try JSONEncoder().encode(route)
        let req = FountainRuntime.HTTPRequest(method: "POST", path: "/routes", headers: ["Content-Type": "application/json"], body: data)
        let resp = await host.createRoute(req)
        if resp.status == 201, let created = try? JSONDecoder().decode(Components.Schemas.RouteInfo.self, from: resp.body) {
            return .created(.init(body: .json(created)))
        } else if resp.status == 409, let err = try? JSONDecoder().decode(Components.Schemas.ErrorResponse.self, from: resp.body) {
            return .conflict(.init(body: .json(err)))
        }
        return .undocumented(statusCode: resp.status, OpenAPIRuntime.UndocumentedPayload())
    }

    public func updateRoute(_ input: Operations.updateRoute.Input) async throws -> Operations.updateRoute.Output {
        guard case let .json(route) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let data = try JSONEncoder().encode(route)
        let req = FountainRuntime.HTTPRequest(method: "PUT", path: "/routes/\(input.path.routeId)", headers: ["Content-Type": "application/json"], body: data)
        let resp = await host.updateRoute(input.path.routeId, request: req)
        if resp.status == 200, let updated = try? JSONDecoder().decode(Components.Schemas.RouteInfo.self, from: resp.body) {
            return .ok(.init(body: .json(updated)))
        } else if resp.status == 404, let err = try? JSONDecoder().decode(Components.Schemas.ErrorResponse.self, from: resp.body) {
            return .notFound(.init(body: .json(err)))
        }
        return .undocumented(statusCode: resp.status, OpenAPIRuntime.UndocumentedPayload())
    }

    public func deleteRoute(_ input: Operations.deleteRoute.Input) async throws -> Operations.deleteRoute.Output {
        let resp = await host.deleteRoute(input.path.routeId)
        if resp.status == 204 {
            return .noContent(.init())
        } else if resp.status == 404, let err = try? JSONDecoder().decode(Components.Schemas.ErrorResponse.self, from: resp.body) {
            return .notFound(.init(body: .json(err)))
        }
        return .undocumented(statusCode: resp.status, OpenAPIRuntime.UndocumentedPayload())
    }
}

private extension GatewayOpenAPI {
    static var iso8601WithFractional: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    static var iso8601Basic: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    static let queryAllowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    static let maxMultipartBytes = 64 * 1024 * 1024

    func unavailablePayload() -> OpenAPIRuntime.UndocumentedPayload {
        let body = try? JSONEncoder().encode(["error": "chatkit plugin unavailable"])
        var fields = HTTPFields()
        fields[.contentType] = "application/json"
        return OpenAPIRuntime.UndocumentedPayload(headerFields: fields, body: body.map { HTTPBody($0) })
    }

    func undocumentedPayload(status: Int, error: ChatKitGeneratedHandlers.OperationError) -> OpenAPIRuntime.UndocumentedPayload {
        let body = try? JSONEncoder().encode(["error": error.message, "code": error.code])
        var fields = HTTPFields()
        fields[.contentType] = "application/json"
        return OpenAPIRuntime.UndocumentedPayload(headerFields: fields, body: body.map { HTTPBody($0) })
    }

    func makeErrorBody(_ error: ChatKitGeneratedHandlers.OperationError) -> Components.Schemas.ErrorResponse {
        Components.Schemas.ErrorResponse(error: "[\(error.code)] \(error.message)")
    }

    func convertSessionResponse(_ response: ChatKitSessionResponse) throws -> Components.Schemas.ChatKitSessionResponse {
        let expires = try parseDate(response.expires_at)
        let metadata = response.metadata.map { Components.Schemas.ChatKitSessionResponse.metadataPayload(additionalProperties: $0) }
        return Components.Schemas.ChatKitSessionResponse(
            session_id: response.session_id,
            client_secret: response.client_secret,
            expires_at: expires,
            metadata: metadata
        )
    }

    func convertMessageRequest(_ request: Components.Schemas.ChatKitMessageRequest) throws -> ChatKitMessageRequest {
        let messages = try request.messages.map { try convertMessage($0) }
        return ChatKitMessageRequest(
            client_secret: request.client_secret,
            thread_id: request.thread_id,
            messages: messages,
            stream: request.stream,
            metadata: request.metadata?.additionalProperties
        )
    }

    func convertMessage(_ message: Components.Schemas.ChatKitMessage) throws -> ChatKitMessage {
        let created = message.created_at.map { formatDate($0) }
        let attachments = message.attachments?.map { convertAttachment($0) }
        return ChatKitMessage(
            id: message.id,
            role: message.role.rawValue,
            content: message.content,
            created_at: created,
            attachments: attachments
        )
    }

    func convertMessageResponse(_ response: ChatKitMessageResponse) throws -> Components.Schemas.ChatKitMessageResponse {
        let created = try parseDate(response.created_at)
        let usage = response.usage.map { Components.Schemas.ChatKitMessageResponse.usagePayload(additionalProperties: $0) }
        let metadata = response.metadata.map { Components.Schemas.ChatKitMessageResponse.metadataPayload(additionalProperties: $0) }
        return Components.Schemas.ChatKitMessageResponse(
            answer: response.answer,
            thread_id: response.thread_id,
            response_id: response.response_id,
            created_at: created,
            usage: usage,
            provider: response.provider,
            model: response.model,
            metadata: metadata
        )
    }

    func convertUploadResponse(_ response: ChatKitUploadResponse) -> Components.Schemas.ChatKitUploadResponse {
        Components.Schemas.ChatKitUploadResponse(
            attachment_id: response.attachment_id,
            upload_url: response.upload_url,
            mime_type: response.mime_type
        )
    }

    func convertThreadListResponse(_ response: ChatKitThreadListResponse) throws -> Components.Schemas.ChatKitThreadListResponse {
        let threads = try response.threads.map { try convertThreadSummary($0) }
        return Components.Schemas.ChatKitThreadListResponse(threads: threads)
    }

    func convertThreadSummary(_ summary: ChatKitThreadSummary) throws -> Components.Schemas.ChatKitThreadSummary {
        let created = try parseDate(summary.created_at)
        let updated = try parseDate(summary.updated_at)
        return Components.Schemas.ChatKitThreadSummary(
            thread_id: summary.thread_id,
            session_id: summary.session_id,
            title: summary.title,
            created_at: created,
            updated_at: updated,
            message_count: summary.message_count
        )
    }

    func convertThread(_ thread: ChatKitThread) throws -> Components.Schemas.ChatKitThread {
        let created = try parseDate(thread.created_at)
        let updated = try parseDate(thread.updated_at)
        let metadata = thread.metadata.map { Components.Schemas.ChatKitThread.metadataPayload(additionalProperties: $0) }
        let messages = try thread.messages.map { try convertThreadMessage($0) }
        return Components.Schemas.ChatKitThread(
            thread_id: thread.thread_id,
            session_id: thread.session_id,
            title: thread.title,
            created_at: created,
            updated_at: updated,
            metadata: metadata,
            messages: messages
        )
    }

    func convertThreadMessage(_ message: ChatKitThreadMessage) throws -> Components.Schemas.ChatKitThreadMessage {
        let created = try parseDate(message.created_at)
        let attachments = message.attachments?.map { convertAttachment($0) }
        let toolCalls = message.tool_calls?.map { convertToolCall($0) }
        let usage = message.usage.map { Components.Schemas.ChatKitThreadMessage.usagePayload(additionalProperties: $0) }
        return Components.Schemas.ChatKitThreadMessage(
            id: message.id,
            role: message.role,
            content: message.content,
            created_at: created,
            attachments: attachments,
            tool_calls: toolCalls,
            response_id: message.response_id,
            usage: usage
        )
    }

    func convertToolCall(_ call: ChatKitToolCall) -> Components.Schemas.ChatKitToolCall {
        Components.Schemas.ChatKitToolCall(
            id: call.id,
            name: call.name,
            arguments: call.arguments,
            status: call.status,
            result: call.result
        )
    }

    func convertAttachment(_ attachment: Components.Schemas.ChatKitAttachment) -> ChatKitAttachment {
        ChatKitAttachment(
            id: attachment.id,
            type: attachment._type.rawValue,
            name: attachment.name,
            mime_type: attachment.mime_type,
            size_bytes: attachment.size_bytes
        )
    }

    func convertAttachment(_ attachment: ChatKitAttachment) -> Components.Schemas.ChatKitAttachment {
        let payload = Components.Schemas.ChatKitAttachment._typePayload(rawValue: attachment.type) ?? .file
        return Components.Schemas.ChatKitAttachment(
            id: attachment.id,
            _type: payload,
            name: attachment.name,
            mime_type: attachment.mime_type,
            size_bytes: attachment.size_bytes
        )
    }

    func parseUploadPayload(_ body: Operations.uploadChatKitAttachment.Input.Body) async throws -> ChatKitGeneratedHandlers.UploadPayload {
        switch body {
        case .multipartForm(let multipart):
            var clientSecret: String?
            var threadId: String?
            var fileData: Data?
            var fileName: String?
            let mimeType = "application/octet-stream"

            for try await part in multipart {
                switch part {
                case .client_secret(let wrapper):
                    clientSecret = try await string(from: wrapper.payload.body).trimmingCharacters(in: .whitespacesAndNewlines)
                case .thread_id(let wrapper):
                    let value = try await string(from: wrapper.payload.body).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { threadId = value }
                case .file(let wrapper):
                    fileData = try await collectBody(wrapper.payload.body)
                    fileName = wrapper.filename ?? "attachment"
                case .undocumented(let raw):
                    let name = raw.headerFields[.contentDisposition] ?? ""
                    let value = try await string(from: raw.body).trimmingCharacters(in: .whitespacesAndNewlines)
                    if name.contains("client_secret") { clientSecret = value }
                    if name.contains("thread_id") && !value.isEmpty { threadId = value }
                }
            }

            guard let secret = clientSecret, let data = fileData, let finalName = fileName else {
                throw ChatKitGeneratedHandlers.OperationError(status: 400, code: "invalid_request", message: "multipart form missing required parts")
            }

            return ChatKitGeneratedHandlers.UploadPayload(
                clientSecret: secret,
                threadId: threadId,
                fileName: finalName,
                mimeType: mimeType,
                data: data
            )
        }
    }

    func collectBody(_ body: OpenAPIRuntime.HTTPBody) async throws -> Data {
        try await Data(collecting: body, upTo: Self.maxMultipartBytes)
    }

    func string(from body: OpenAPIRuntime.HTTPBody) async throws -> String {
        let data = try await collectBody(body)
        return String(decoding: data, as: UTF8.self)
    }

    func parseDate(_ string: String) throws -> Date {
        if let date = Self.iso8601WithFractional.date(from: string) ?? Self.iso8601Basic.date(from: string) {
            return date
        }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid date: \(string)"))
    }

    func formatDate(_ date: Date) -> String {
        Self.iso8601WithFractional.string(from: date)
    }
}
