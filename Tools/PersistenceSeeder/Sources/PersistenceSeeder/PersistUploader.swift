import Foundation
import ApiClientsCore

struct PersistUploader {
    private let client: PersistServiceClient

    init(baseURL: URL, apiKey: String?) {
        self.client = PersistServiceClient(baseURL: baseURL, apiKey: apiKey)
    }

    func apply(manifest: SeedManifest, speeches: [TheFourStarsParser.Speech], uploadLimit: Int? = nil) async throws {
        try await ensureCorpus(manifest.corpusId)
        let payloadSpeeches: [TheFourStarsParser.Speech]
        if let uploadLimit, uploadLimit > 0 {
            payloadSpeeches = Array(speeches.prefix(uploadLimit))
        } else {
            payloadSpeeches = speeches
        }
        try await uploadPagesAndSegments(corpusId: manifest.corpusId, speeches: payloadSpeeches)
    }

    private func ensureCorpus(_ corpusId: String) async throws {
        let existing = try await client.listCorpora()
        if existing.contains(where: { $0 == corpusId }) {
            return
        }
        do {
            try await client.createCorpus(corpusId: corpusId)
        } catch APIError.httpStatus(let status, _) where status == 409 {
            return
        }
    }

    private func uploadPagesAndSegments(corpusId: String, speeches: [TheFourStarsParser.Speech]) async throws {
        var uploadedPages = Set<String>()
        let host = "the-four-stars"

        for speech in speeches {
            let pageId = pageIdentifier(for: speech)
            if uploadedPages.insert(pageId).inserted {
                let page = PersistServiceClient.PagePayload(
                    corpusId: corpusId,
                    pageId: pageId,
                    url: "the-four-stars://\(pageId)",
                    host: host,
                    title: pageTitle(for: speech)
                )
                try await callIgnoringConflict { try await client.addPage(corpusId: corpusId, page: page) }
            }

            let segmentId = segmentIdentifier(for: speech)
            let text = speech.lines.joined(separator: "\n")
            let segment = PersistServiceClient.SegmentPayload(
                corpusId: corpusId,
                segmentId: segmentId,
                pageId: pageId,
                kind: "speech",
                text: text
            )
            try await callIgnoringConflict { try await client.addSegment(corpusId: corpusId, segment: segment) }
        }
    }

    private func callIgnoringConflict(_ operation: @escaping () async throws -> Void) async throws {
        do {
            try await operation()
        } catch APIError.httpStatus(let status, _) where status == 409 {
            return
        }
    }

    private func pageIdentifier(for speech: TheFourStarsParser.Speech) -> String {
        "act-\(slugify(speech.act))-scene-\(slugify(speech.scene))"
    }

    private func segmentIdentifier(for speech: TheFourStarsParser.Speech) -> String {
        "\(slugify(speech.speaker))-\(speech.index)"
    }

    private func pageTitle(for speech: TheFourStarsParser.Speech) -> String {
        let location = speech.location.isEmpty ? "" : " – \(speech.location)"
        return "Act \(speech.act) Scene \(speech.scene)\(location)"
    }

    private func slugify(_ value: String) -> String {
        let lowered = value.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        var cleaned = lowered.replacingOccurrences(of: " ", with: "-")
        cleaned = cleaned.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }.map(String.init).joined()
        cleaned = cleaned.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

private struct PersistServiceClient {
    struct PagePayload: Codable, Sendable {
        let corpusId: String
        let pageId: String
        let url: String
        let host: String
        let title: String
    }

    struct SegmentPayload: Codable, Sendable {
        let corpusId: String
        let segmentId: String
        let pageId: String
        let kind: String
        let text: String
    }

    struct ListCorporaResponse: Codable {
        let total: Int
        let corpora: [String]
    }

    private let rest: RESTClient
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL, apiKey: String?) {
        var headers = ["Accept": "application/json"]
        if let apiKey { headers["X-API-Key"] = apiKey }
        rest = RESTClient(baseURL: baseURL, defaultHeaders: headers)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func listCorpora() async throws -> [String] {
        guard let url = rest.buildURL(path: "/corpora") else { throw APIError.invalidURL }
        let response = try await rest.send(APIRequest(method: .GET, url: url))
        let payload = try decoder.decode(ListCorporaResponse.self, from: response.data)
        return payload.corpora
    }

    func createCorpus(corpusId: String) async throws {
        guard let url = rest.buildURL(path: "/corpora") else { throw APIError.invalidURL }
        let body = try encoder.encode(["corpusId": corpusId])
        _ = try await rest.send(APIRequest(method: .POST, url: url, headers: ["Content-Type": "application/json"], body: body))
    }

    func addPage(corpusId: String, page: PagePayload) async throws {
        guard let url = rest.buildURL(path: "/corpora/\(corpusId)/pages") else { throw APIError.invalidURL }
        let body = try encoder.encode(page)
        _ = try await rest.send(APIRequest(method: .POST, url: url, headers: ["Content-Type": "application/json"], body: body))
    }

    func addSegment(corpusId: String, segment: SegmentPayload) async throws {
        guard let url = rest.buildURL(path: "/corpora/\(corpusId)/segments") else { throw APIError.invalidURL }
        let body = try encoder.encode(segment)
        _ = try await rest.send(APIRequest(method: .POST, url: url, headers: ["Content-Type": "application/json"], body: body))
    }
}
