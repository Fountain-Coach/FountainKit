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
        if resp.status == 200, let tok = try? JSONDecoder().decode(Components.Schemas.TokenResponse.self, from: resp.body) {
            return .ok(.init(body: .json(tok)))
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
