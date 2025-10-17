import PolicyGatewayPlugin
import FountainRuntime

extension PolicyGatewayPlugin: GatewayPlugin {
    public func prepare(_ request: HTTPRequest) async throws -> HTTPRequest {
        // allow-all for now
        return request
    }
}

