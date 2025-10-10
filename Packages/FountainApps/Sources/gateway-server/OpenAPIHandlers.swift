import Foundation
import OpenAPIRuntime

// Generated handlers bridge to GatewayServer logic.
public struct GatewayOpenAPI: APIProtocol, @unchecked Sendable {
    let host: GatewayServer
    public init(host: GatewayServer) { self.host = host }

    public func gatewayHealth(_ input: Operations.gatewayHealth.Input) async throws -> Operations.gatewayHealth.Output {
        // Host returns a JSON object; we just respond with an empty object for simplicity.
        let payload = try Operations.gatewayHealth.Output.Ok.Body.jsonPayload(unvalidatedValue: [:])
        return .ok(.init(body: .json(payload)))
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
        if resp.status == 200, let tok = try? JSONDecoder().decode(Components.Schemas.TokenResponse.self, from: resp.body) {
            return .ok(.init(body: .json(tok)))
        } else if resp.status == 401, let err = try? JSONDecoder().decode(Components.Schemas.ErrorResponse.self, from: resp.body) {
            return .unauthorized(.init(body: .json(err)))
        }
        return .undocumented(statusCode: resp.status, OpenAPIRuntime.UndocumentedPayload())
    }

    public func certificateInfo(_ input: Operations.certificateInfo.Input) async throws -> Operations.certificateInfo.Output {
        let resp = host.certificateInfo()
        if resp.status == 200, let info = try? JSONDecoder().decode(Components.Schemas.CertificateInfo.self, from: resp.body) {
            return .ok(.init(body: .json(info)))
        }
        return .undocumented(statusCode: resp.status, OpenAPIRuntime.UndocumentedPayload())
    }

    public func renewCertificate(_ input: Operations.renewCertificate.Input) async throws -> Operations.renewCertificate.Output {
        let resp = host.renewCertificate()
        if resp.status == 202 {
            // Any JSON object is acceptable per spec
            let payload = try Operations.renewCertificate.Output.Accepted.Body.jsonPayload(unvalidatedValue: ["status": "triggered"])
            return .accepted(.init(body: .json(payload)))
        }
        return .undocumented(statusCode: resp.status, OpenAPIRuntime.UndocumentedPayload())
    }

    public func listRoutes(_ input: Operations.listRoutes.Input) async throws -> Operations.listRoutes.Output {
        let resp = host.listRoutes()
        if resp.status == 200, let routes = try? JSONDecoder().decode([Components.Schemas.RouteInfo].self, from: resp.body) {
            let payload = Operations.listRoutes.Output.Ok.Body.jsonPayload(routes)
            return .ok(.init(body: .json(payload)))
        }
        return .undocumented(statusCode: resp.status, OpenAPIRuntime.UndocumentedPayload())
    }

    public func createRoute(_ input: Operations.createRoute.Input) async throws -> Operations.createRoute.Output {
        guard case let .json(route) = input.body else { return .undocumented(statusCode: 422, OpenAPIRuntime.UndocumentedPayload()) }
        let data = try JSONEncoder().encode(route)
        let req = HTTPRequest(method: "POST", path: "/routes", headers: ["Content-Type": "application/json"], body: data)
        let resp = host.createRoute(req)
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
        let req = HTTPRequest(method: "PUT", path: "/routes/\(input.path.routeId)", headers: ["Content-Type": "application/json"], body: data)
        let resp = host.updateRoute(input.path.routeId, request: req)
        if resp.status == 200, let updated = try? JSONDecoder().decode(Components.Schemas.RouteInfo.self, from: resp.body) {
            return .ok(.init(body: .json(updated)))
        } else if resp.status == 404, let err = try? JSONDecoder().decode(Components.Schemas.ErrorResponse.self, from: resp.body) {
            return .notFound(.init(body: .json(err)))
        }
        return .undocumented(statusCode: resp.status, OpenAPIRuntime.UndocumentedPayload())
    }

    public func deleteRoute(_ input: Operations.deleteRoute.Input) async throws -> Operations.deleteRoute.Output {
        let resp = host.deleteRoute(input.path.routeId)
        if resp.status == 204 {
            return .noContent(.init())
        } else if resp.status == 404, let err = try? JSONDecoder().decode(Components.Schemas.ErrorResponse.self, from: resp.body) {
            return .notFound(.init(body: .json(err)))
        }
        return .undocumented(statusCode: resp.status, OpenAPIRuntime.UndocumentedPayload())
    }
}

