import Foundation
import ApiClientsCore

public struct PersistServiceClient: Sendable {
    public struct PagePayload: Codable, Sendable {
        public let corpusId: String
        public let pageId: String
        public let url: String
        public let host: String
        public let title: String

        public init(corpusId: String, pageId: String, url: String, host: String, title: String) {
            self.corpusId = corpusId
            self.pageId = pageId
            self.url = url
            self.host = host
            self.title = title
        }
    }

    public struct SegmentPayload: Codable, Sendable {
        public let corpusId: String
        public let segmentId: String
        public let pageId: String
        public let kind: String
        public let text: String

        public init(corpusId: String, segmentId: String, pageId: String, kind: String, text: String) {
            self.corpusId = corpusId
            self.segmentId = segmentId
            self.pageId = pageId
            self.kind = kind
            self.text = text
        }
    }

    public struct Page: Codable, Sendable {
        public let corpusId: String
        public let pageId: String
        public let url: String
        public let host: String
        public let title: String

        public init(corpusId: String, pageId: String, url: String, host: String, title: String) {
            self.corpusId = corpusId
            self.pageId = pageId
            self.url = url
            self.host = host
            self.title = title
        }
    }

    public struct Segment: Codable, Sendable {
        public let corpusId: String
        public let segmentId: String
        public let pageId: String
        public let kind: String
        public let text: String

        public init(corpusId: String, segmentId: String, pageId: String, kind: String, text: String) {
            self.corpusId = corpusId
            self.segmentId = segmentId
            self.pageId = pageId
            self.kind = kind
            self.text = text
        }
    }

    public struct PageList: Sendable {
        public let total: Int
        public let pages: [Page]
    }

    public struct SegmentList: Sendable {
        public let total: Int
        public let segments: [Segment]
    }

    private struct ListCorporaResponse: Codable {
        let total: Int
        let corpora: [String]
    }

    private struct PageListResponse: Codable {
        let total: Int
        let pages: [Page]
    }

    private struct SegmentListResponse: Codable {
        let total: Int
        let segments: [Segment]
    }

    private let rest: RESTClient
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseURL: URL, apiKey: String?) {
        var headers = ["Accept": "application/json"]
        if let apiKey { headers["X-API-Key"] = apiKey }
        self.rest = RESTClient(baseURL: baseURL, defaultHeaders: headers)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: - Corpus Management

    public func listCorpora() async throws -> [String] {
        guard let url = rest.buildURL(path: "/corpora") else { throw APIError.invalidURL }
        let response = try await rest.send(APIRequest(method: .GET, url: url))
        let payload = try decoder.decode(ListCorporaResponse.self, from: response.data)
        return payload.corpora
    }

    public func createCorpus(corpusId: String) async throws {
        guard let url = rest.buildURL(path: "/corpora") else { throw APIError.invalidURL }
        let body = try encoder.encode(["corpusId": corpusId])
        _ = try await rest.send(APIRequest(method: .POST, url: url, headers: ["Content-Type": "application/json"], body: body))
    }

    // MARK: - Write Operations

    public func addPage(corpusId: String, page: PagePayload) async throws {
        guard let url = rest.buildURL(path: "/corpora/\(corpusId)/pages") else { throw APIError.invalidURL }
        let body = try encoder.encode(page)
        _ = try await rest.send(APIRequest(method: .POST, url: url, headers: ["Content-Type": "application/json"], body: body))
    }

    public func addSegment(corpusId: String, segment: SegmentPayload) async throws {
        guard let url = rest.buildURL(path: "/corpora/\(corpusId)/segments") else { throw APIError.invalidURL }
        let body = try encoder.encode(segment)
        _ = try await rest.send(APIRequest(method: .POST, url: url, headers: ["Content-Type": "application/json"], body: body))
    }

    // MARK: - Read Operations

    public func listPages(
        corpusId: String,
        limit: Int = 50,
        offset: Int = 0,
        query: String? = nil
    ) async throws -> PageList {
        var queryDictionary: [String: String?] = [
            "limit": "\(limit)",
            "offset": "\(offset)"
        ]
        if let query, !query.isEmpty {
            queryDictionary["q"] = query
        }

        guard let url = rest.buildURL(path: "/corpora/\(corpusId)/pages", query: queryDictionary) else {
            throw APIError.invalidURL
        }
        let response = try await rest.send(APIRequest(method: .GET, url: url))
        let payload = try decoder.decode(PageListResponse.self, from: response.data)
        return PageList(total: payload.total, pages: payload.pages)
    }

    public func listSegments(
        corpusId: String,
        limit: Int = 50,
        offset: Int = 0,
        query: String? = nil
    ) async throws -> SegmentList {
        var queryItems: [String: String?] = [
            "limit": "\(limit)",
            "offset": "\(offset)"
        ]
        if let query, !query.isEmpty {
            queryItems["q"] = query
        }
        guard let url = rest.buildURL(path: "/corpora/\(corpusId)/segments", query: queryItems) else {
            throw APIError.invalidURL
        }
        let response = try await rest.send(APIRequest(method: .GET, url: url))
        let payload = try decoder.decode(SegmentListResponse.self, from: response.data)
        return SegmentList(total: payload.total, segments: payload.segments)
    }
}
