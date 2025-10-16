import Foundation
import OpenAPIRuntime
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
        .undocumented(statusCode: 501, OpenAPIRuntime.UndocumentedPayload())
    }

    public func refreshChatKitSession(_ input: Operations.refreshChatKitSession.Input) async throws -> Operations.refreshChatKitSession.Output {
        .undocumented(statusCode: 501, OpenAPIRuntime.UndocumentedPayload())
    }

    public func postChatKitMessage(_ input: Operations.postChatKitMessage.Input) async throws -> Operations.postChatKitMessage.Output {
        .undocumented(statusCode: 501, OpenAPIRuntime.UndocumentedPayload())
    }

    public func uploadChatKitAttachment(_ input: Operations.uploadChatKitAttachment.Input) async throws -> Operations.uploadChatKitAttachment.Output {
        .undocumented(statusCode: 501, OpenAPIRuntime.UndocumentedPayload())
    }

    public func downloadChatKitAttachment(_ input: Operations.downloadChatKitAttachment.Input) async throws -> Operations.downloadChatKitAttachment.Output {
        .undocumented(statusCode: 501, OpenAPIRuntime.UndocumentedPayload())
    }

    public func listChatKitThreads(_ input: Operations.listChatKitThreads.Input) async throws -> Operations.listChatKitThreads.Output {
        .undocumented(statusCode: 501, OpenAPIRuntime.UndocumentedPayload())
    }

    public func createChatKitThread(_ input: Operations.createChatKitThread.Input) async throws -> Operations.createChatKitThread.Output {
        .undocumented(statusCode: 501, OpenAPIRuntime.UndocumentedPayload())
    }

    public func getChatKitThread(_ input: Operations.getChatKitThread.Input) async throws -> Operations.getChatKitThread.Output {
        .undocumented(statusCode: 501, OpenAPIRuntime.UndocumentedPayload())
    }

    public func deleteChatKitThread(_ input: Operations.deleteChatKitThread.Input) async throws -> Operations.deleteChatKitThread.Output {
        .undocumented(statusCode: 501, OpenAPIRuntime.UndocumentedPayload())
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
