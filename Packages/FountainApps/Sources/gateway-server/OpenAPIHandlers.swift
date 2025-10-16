import Foundation
import OpenAPIRuntime
import HTTPTypes
import FountainRuntime

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
        var headers: [String: String] = [:]
        if let accept = input.headers.accept.first {
            headers["Accept"] = accept.rawValue
        }

        var bodyData = Data()
        if let body = input.body {
            switch body {
            case .json(let payload):
                bodyData = try encodeJSON(payload)
                headers["Content-Type"] = "application/json"
            }
        }

        let response = await host.dispatchChatKitRequest(
            method: "POST",
            path: "/chatkit/session",
            headers: headers,
            body: bodyData
        )

        switch response.status {
        case 201:
            if let payload = try? decodeJSON(response.body, as: Components.Schemas.ChatKitSessionResponse.self) {
                return .created(.init(body: .json(payload)))
            }
        case 400:
            if let error = decodeErrorResponse(response.body) {
                return .badRequest(.init(body: .json(error)))
            }
        default:
            break
        }

        return .undocumented(statusCode: response.status, makeUndocumentedPayload(from: response))
    }

    public func refreshChatKitSession(_ input: Operations.refreshChatKitSession.Input) async throws -> Operations.refreshChatKitSession.Output {
        var headers: [String: String] = [:]
        if let accept = input.headers.accept.first {
            headers["Accept"] = accept.rawValue
        }

        let bodyData: Data
        switch input.body {
        case .json(let payload):
            bodyData = try encodeJSON(payload)
            headers["Content-Type"] = "application/json"
        }

        let response = await host.dispatchChatKitRequest(
            method: "POST",
            path: "/chatkit/session/refresh",
            headers: headers,
            body: bodyData
        )

        switch response.status {
        case 200:
            if let payload = try? decodeJSON(response.body, as: Components.Schemas.ChatKitSessionResponse.self) {
                return .ok(.init(body: .json(payload)))
            }
        case 400:
            if let error = decodeErrorResponse(response.body) {
                return .badRequest(.init(body: .json(error)))
            }
        case 401:
            if let error = decodeErrorResponse(response.body) {
                return .unauthorized(.init(body: .json(error)))
            }
        default:
            break
        }

        return .undocumented(statusCode: response.status, makeUndocumentedPayload(from: response))
    }

    public func postChatKitMessage(_ input: Operations.postChatKitMessage.Input) async throws -> Operations.postChatKitMessage.Output {
        var headers: [String: String] = [:]
        if let accept = input.headers.accept.first {
            headers["Accept"] = accept.rawValue
        }

        let bodyData: Data
        switch input.body {
        case .json(let payload):
            bodyData = try encodeJSON(payload)
            headers["Content-Type"] = "application/json"
        }

        let response = await host.dispatchChatKitRequest(
            method: "POST",
            path: "/chatkit/messages",
            headers: headers,
            body: bodyData
        )

        switch response.status {
        case 200:
            if let payload = try? decodeJSON(response.body, as: Components.Schemas.ChatKitMessageResponse.self) {
                return .ok(.init(body: .json(payload)))
            }
        case 202:
            let body = OpenAPIRuntime.HTTPBody(response.body)
            return .accepted(.init(body: .text_event_hyphen_stream(body)))
        case 400:
            if let error = decodeErrorResponse(response.body) {
                return .badRequest(.init(body: .json(error)))
            }
        case 401:
            if let error = decodeErrorResponse(response.body) {
                return .unauthorized(.init(body: .json(error)))
            }
        default:
            break
        }

        return .undocumented(statusCode: response.status, makeUndocumentedPayload(from: response))
    }

    public func uploadChatKitAttachment(_ input: Operations.uploadChatKitAttachment.Input) async throws -> Operations.uploadChatKitAttachment.Output {
        var headers: [String: String] = [:]
        if let accept = input.headers.accept.first {
            headers["Accept"] = accept.rawValue
        }

        let (bodyData, boundary) = try await encodeMultipart(input.body)
        headers["Content-Type"] = "multipart/form-data; boundary=\(boundary)"
        headers["Content-Length"] = "\(bodyData.count)"

        let response = await host.dispatchChatKitRequest(
            method: "POST",
            path: "/chatkit/upload",
            headers: headers,
            body: bodyData
        )

        switch response.status {
        case 201:
            if let payload = try? decodeJSON(response.body, as: Components.Schemas.ChatKitUploadResponse.self) {
                return .created(.init(body: .json(payload)))
            }
        case 400:
            if let error = decodeErrorResponse(response.body) {
                return .badRequest(.init(body: .json(error)))
            }
        case 401:
            if let error = decodeErrorResponse(response.body) {
                return .unauthorized(.init(body: .json(error)))
            }
        default:
            break
        }

        return .undocumented(statusCode: response.status, makeUndocumentedPayload(from: response))
    }

    public func downloadChatKitAttachment(_ input: Operations.downloadChatKitAttachment.Input) async throws -> Operations.downloadChatKitAttachment.Output {
        var headers: [String: String] = [:]
        if let accept = input.headers.accept.first {
            headers["Accept"] = accept.rawValue
        }

        let query = makeQueryString(["client_secret": input.query.client_secret])
        let response = await host.dispatchChatKitRequest(
            method: "GET",
            path: "/chatkit/attachments/\(input.path.attachmentId)\(query)",
            headers: headers
        )

        switch response.status {
        case 200:
            let okHeaders = Operations.downloadChatKitAttachment.Output.Ok.Headers(
                Cache_hyphen_Control: response.headers["Cache-Control"],
                Content_hyphen_Disposition: response.headers["Content-Disposition"],
                ETag: response.headers["ETag"]
            )
            return .ok(.init(headers: okHeaders, body: .binary(HTTPBody(response.body))))
        case 400:
            if let error = decodeErrorResponse(response.body) {
                return .badRequest(.init(body: .json(error)))
            }
        case 401:
            if let error = decodeErrorResponse(response.body) {
                return .unauthorized(.init(body: .json(error)))
            }
        case 403:
            if let error = decodeErrorResponse(response.body) {
                return .forbidden(.init(body: .json(error)))
            }
        case 404:
            if let error = decodeErrorResponse(response.body) {
                return .notFound(.init(body: .json(error)))
            }
        case 409:
            if let error = decodeErrorResponse(response.body) {
                return .conflict(.init(body: .json(error)))
            }
        default:
            break
        }

        return .undocumented(statusCode: response.status, makeUndocumentedPayload(from: response))
    }

    public func listChatKitThreads(_ input: Operations.listChatKitThreads.Input) async throws -> Operations.listChatKitThreads.Output {
        var headers: [String: String] = [:]
        if let accept = input.headers.accept.first {
            headers["Accept"] = accept.rawValue
        }

        let query = makeQueryString(["client_secret": input.query.client_secret])
        let response = await host.dispatchChatKitRequest(
            method: "GET",
            path: "/chatkit/threads\(query)",
            headers: headers
        )

        switch response.status {
        case 200:
            if let payload = try? decodeJSON(response.body, as: Components.Schemas.ChatKitThreadListResponse.self) {
                return .ok(.init(body: .json(payload)))
            }
        case 400:
            if let error = decodeErrorResponse(response.body) {
                return .badRequest(.init(body: .json(error)))
            }
        case 401:
            if let error = decodeErrorResponse(response.body) {
                return .unauthorized(.init(body: .json(error)))
            }
        default:
            break
        }

        return .undocumented(statusCode: response.status, makeUndocumentedPayload(from: response))
    }

    public func createChatKitThread(_ input: Operations.createChatKitThread.Input) async throws -> Operations.createChatKitThread.Output {
        var headers: [String: String] = [:]
        if let accept = input.headers.accept.first {
            headers["Accept"] = accept.rawValue
        }

        let bodyData: Data
        switch input.body {
        case .json(let payload):
            bodyData = try encodeJSON(payload)
            headers["Content-Type"] = "application/json"
        }

        let response = await host.dispatchChatKitRequest(
            method: "POST",
            path: "/chatkit/threads",
            headers: headers,
            body: bodyData
        )

        switch response.status {
        case 201:
            if let payload = try? decodeJSON(response.body, as: Components.Schemas.ChatKitThread.self) {
                return .created(.init(body: .json(payload)))
            }
        case 400:
            if let error = decodeErrorResponse(response.body) {
                return .badRequest(.init(body: .json(error)))
            }
        case 401:
            if let error = decodeErrorResponse(response.body) {
                return .unauthorized(.init(body: .json(error)))
            }
        default:
            break
        }

        return .undocumented(statusCode: response.status, makeUndocumentedPayload(from: response))
    }

    public func getChatKitThread(_ input: Operations.getChatKitThread.Input) async throws -> Operations.getChatKitThread.Output {
        var headers: [String: String] = [:]
        if let accept = input.headers.accept.first {
            headers["Accept"] = accept.rawValue
        }

        let query = makeQueryString(["client_secret": input.query.client_secret])
        let response = await host.dispatchChatKitRequest(
            method: "GET",
            path: "/chatkit/threads/\(input.path.threadId)\(query)",
            headers: headers
        )

        switch response.status {
        case 200:
            if let payload = try? decodeJSON(response.body, as: Components.Schemas.ChatKitThread.self) {
                return .ok(.init(body: .json(payload)))
            }
        case 400:
            if let error = decodeErrorResponse(response.body) {
                return .badRequest(.init(body: .json(error)))
            }
        case 401:
            if let error = decodeErrorResponse(response.body) {
                return .unauthorized(.init(body: .json(error)))
            }
        case 404:
            if let error = decodeErrorResponse(response.body) {
                return .notFound(.init(body: .json(error)))
            }
        default:
            break
        }

        return .undocumented(statusCode: response.status, makeUndocumentedPayload(from: response))
    }

    public func deleteChatKitThread(_ input: Operations.deleteChatKitThread.Input) async throws -> Operations.deleteChatKitThread.Output {
        var headers: [String: String] = [:]
        if let accept = input.headers.accept.first {
            headers["Accept"] = accept.rawValue
        }

        let query = makeQueryString(["client_secret": input.query.client_secret])
        let response = await host.dispatchChatKitRequest(
            method: "DELETE",
            path: "/chatkit/threads/\(input.path.threadId)\(query)",
            headers: headers
        )

        switch response.status {
        case 204:
            return .noContent(.init())
        case 400:
            if let error = decodeErrorResponse(response.body) {
                return .badRequest(.init(body: .json(error)))
            }
        case 401:
            if let error = decodeErrorResponse(response.body) {
                return .unauthorized(.init(body: .json(error)))
            }
        case 404:
            if let error = decodeErrorResponse(response.body) {
                return .notFound(.init(body: .json(error)))
            }
        default:
            break
        }

        return .undocumented(statusCode: response.status, makeUndocumentedPayload(from: response))
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

    func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.iso8601WithFractional.string(from: date))
        }
        return try encoder.encode(value)
    }

    func decodeJSON<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = Self.iso8601WithFractional.date(from: value) ?? Self.iso8601Basic.date(from: value) {
                return date
            }
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid ISO8601 date: \(value)"
                )
            )
        }
        return try decoder.decode(T.self, from: data)
    }

    func decodeErrorResponse(_ data: Data) -> Components.Schemas.ErrorResponse? {
        try? decodeJSON(data, as: Components.Schemas.ErrorResponse.self)
    }

    func makeUndocumentedPayload(from response: FountainRuntime.HTTPResponse) -> OpenAPIRuntime.UndocumentedPayload {
        var fields = HTTPFields()
        for (key, value) in response.headers {
            guard let name = HTTPField.Name(key) else { continue }
            fields[name] = value
        }
        let body = response.body.isEmpty ? nil : HTTPBody(response.body)
        return OpenAPIRuntime.UndocumentedPayload(headerFields: fields, body: body)
    }

    func makeQueryString(_ parameters: [String: String]) -> String {
        guard !parameters.isEmpty else { return "" }
        let components = parameters
            .sorted { $0.key < $1.key }
            .map { key, value -> String in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: Self.queryAllowedCharacters) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: Self.queryAllowedCharacters) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
        guard !components.isEmpty else { return "" }
        return "?" + components.joined(separator: "&")
    }

    func collectBody(_ body: OpenAPIRuntime.HTTPBody) async throws -> Data {
        try await Data(collecting: body, upTo: Self.maxMultipartBytes)
    }

    func appendMultipartPart(into data: inout Data, boundary: String, headerLines: [String], body: Data) {
        appendString("--\(boundary)\r\n", to: &data)
        for line in headerLines {
            appendString("\(line)\r\n", to: &data)
        }
        appendString("\r\n", to: &data)
        data.append(body)
        appendString("\r\n", to: &data)
    }

    func appendString(_ string: String, to data: inout Data) {
        if let encoded = string.data(using: .utf8) {
            data.append(encoded)
        }
    }

    func appendClosingBoundary(_ boundary: String, to data: inout Data) {
        appendString("--\(boundary)--\r\n", to: &data)
    }

    func contentDisposition(name: String, filename: String? = nil) -> String {
        var value = "form-data; name=\"\(name)\""
        if let filename {
            value += "; filename=\"\(filename)\""
        }
        return value
    }

    func encodeMultipart(_ body: Operations.uploadChatKitAttachment.Input.Body) async throws -> (Data, String) {
        switch body {
        case .multipartForm(let multipart):
            let boundary = "Boundary-\(UUID().uuidString)"
            var data = Data()
            for try await part in multipart {
                switch part {
                case .client_secret(let wrapper):
                    let bytes = try await collectBody(wrapper.payload.body)
                    appendMultipartPart(
                        into: &data,
                        boundary: boundary,
                        headerLines: ["Content-Disposition: \(contentDisposition(name: "client_secret"))"],
                        body: bytes
                    )
                case .thread_id(let wrapper):
                    let bytes = try await collectBody(wrapper.payload.body)
                    guard !bytes.isEmpty else { continue }
                    appendMultipartPart(
                        into: &data,
                        boundary: boundary,
                        headerLines: ["Content-Disposition: \(contentDisposition(name: "thread_id"))"],
                        body: bytes
                    )
                case .file(let wrapper):
                    let bytes = try await collectBody(wrapper.payload.body)
                    appendMultipartPart(
                        into: &data,
                        boundary: boundary,
                        headerLines: [
                            "Content-Disposition: \(contentDisposition(name: "file", filename: wrapper.filename ?? "attachment"))",
                            "Content-Type: application/octet-stream"
                        ],
                        body: bytes
                    )
                case .undocumented(let raw):
                    let bytes = try await collectBody(raw.body)
                    var headerLines: [String] = []
                    for field in raw.headerFields {
                        headerLines.append("\(field.name.canonicalName): \(field.value)")
                    }
                    if headerLines.isEmpty {
                        headerLines.append("Content-Disposition: form-data")
                    }
                    appendMultipartPart(
                        into: &data,
                        boundary: boundary,
                        headerLines: headerLines,
                        body: bytes
                    )
                }
            }
            appendClosingBoundary(boundary, to: &data)
            return (data, boundary)
        }
    }
}
