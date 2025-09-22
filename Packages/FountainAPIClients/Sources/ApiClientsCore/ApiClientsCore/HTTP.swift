import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum HTTPMethod: String, Sendable {
    case GET, POST, PUT, PATCH, DELETE
}

public struct APIRequest: Sendable {
    public var method: HTTPMethod
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: HTTPMethod, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct APIResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var data: Data
}

public enum APIError: Error, Equatable, Sendable {
    case invalidURL
    case httpStatus(Int, String)
    case decode(String)
}

public final class RESTClient: @unchecked Sendable {
    public let baseURL: URL
    public var defaultHeaders: [String: String]
    private let session: URLSession

    public init(baseURL: URL, defaultHeaders: [String: String] = [:], session: URLSession = .shared) {
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
        self.session = session
    }

    public func send(_ request: APIRequest) async throws -> APIResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        let headers = defaultHeaders.merging(request.headers, uniquingKeysWith: { _, new in new })
        for (k, v) in headers { urlRequest.setValue(v, forHTTPHeaderField: k) }
        urlRequest.httpBody = request.body
        let (data, resp) = try await session.data(for: urlRequest)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.httpStatus(-1, "Non-HTTP response")
        }
        if !(200...299).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpStatus(http.statusCode, text)
        }
        var hdrs: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
            guard let key = k as? String else { continue }
            if let s = v as? String { hdrs[key] = s }
            else { hdrs[key] = String(describing: v) }
        }
        return APIResponse(status: http.statusCode, headers: hdrs, data: data)
    }

    public func buildURL(path: String, query: [String: String?] = [:]) -> URL? {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        comps?.path = baseURL.path.appending("/").appending(trimmed)
        if !query.isEmpty {
            var items: [URLQueryItem] = query.compactMap { (k, v) in
                if let v = v { return URLQueryItem(name: k, value: v) }
                return nil
            }
            // Ensure deterministic ordering for tests and caching
            items.sort { (a, b) in
                if a.name == b.name { return (a.value ?? "") < (b.value ?? "") }
                return a.name < b.name
            }
            comps?.queryItems = items
        }
        return comps?.url
    }
}

public struct EmptyBody: Codable, Sendable {}
