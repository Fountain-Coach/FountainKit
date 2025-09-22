import Foundation
import ApiClientsCore

public actor GatewayClient {
    private let http: RESTClient

    public init(baseURL: URL, bearerToken: String? = nil) {
        var headers: [String: String] = ["Accept": "application/json"]
        if let token = bearerToken { headers["Authorization"] = "Bearer \(token)" }
        self.http = RESTClient(baseURL: baseURL, defaultHeaders: headers)
    }

    public func health() async throws -> JSONValue {
        guard let url = http.buildURL(path: "/health") else { throw APIError.invalidURL }
        let resp = try await http.send(APIRequest(method: .GET, url: url))
        return try JSONDecoder().decode(JSONValue.self, from: resp.data)
    }

    public func metrics() async throws -> JSONValue {
        guard let url = http.buildURL(path: "/metrics") else { throw APIError.invalidURL }
        let resp = try await http.send(APIRequest(method: .GET, url: url))
        return try JSONDecoder().decode(JSONValue.self, from: resp.data)
    }
}

