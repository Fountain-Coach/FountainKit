import Foundation

struct ToolsFactoryFunction: Codable {
    var function_id: String
    var http_method: String?
    var http_path: String?
}

struct ToolsFactoryListResponse: Codable {
    var functions: [ToolsFactoryFunction]?
    var page: Int?
    var page_size: Int?
    var total: Int?
}

enum MinimalToolsFactoryError: Error { case http(Int) }

struct MinimalToolsFactoryClient {
    let baseURL: URL
    let session: URLSession = .shared

    func listTools(page: Int? = nil, pageSize: Int? = nil) async throws -> ToolsFactoryListResponse {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/tools"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = []
        if let page { items.append(.init(name: "page", value: String(page))) }
        if let pageSize { items.append(.init(name: "page_size", value: String(pageSize))) }
        if !items.isEmpty { comps.queryItems = items }
        var req = URLRequest(url: comps.url!); req.httpMethod = "GET"
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MinimalToolsFactoryError.http((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return (try? JSONDecoder().decode(ToolsFactoryListResponse.self, from: data)) ?? ToolsFactoryListResponse(functions: [], page: nil, page_size: nil, total: nil)
    }
}

