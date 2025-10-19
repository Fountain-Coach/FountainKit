import Foundation

protocol AnyHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionClient: AnyHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

enum ConnectionTester {
    static func test(apiKey: String?, endpoint: URL, client: AnyHTTPClient = URLSessionClient()) async -> MemChatController.ConnectionStatus {
        let modelsURL = ProviderResolver.modelsURL(for: endpoint)
        var req = URLRequest(url: modelsURL)
        req.httpMethod = "GET"
        req.timeoutInterval = 3.0
        if let key = apiKey, !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        do {
            let (_, resp) = try await client.data(for: req)
            if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return .ok(modelsURL.host ?? "ok")
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return .fail("HTTP \(code) at /v1/models")
        } catch { return .fail(error.localizedDescription) }
    }
}

