import Foundation
import ApiClientsCore

public struct PersistUploader: Sendable {
    private let client: PersistServiceClient

    public init(baseURL: URL, apiKey: String?) {
        self.client = PersistServiceClient(baseURL: baseURL, apiKey: apiKey)
    }

    public func apply(
        manifest: SeedManifest,
        speeches: [FountainPlayParser.Speech],
        uploadLimit: Int? = nil,
        hostOverride: String? = nil,
        pagePrefix: String? = nil
    ) async throws {
        try await ensureCorpus(manifest.corpusId)
        let payloadSpeeches: [FountainPlayParser.Speech]
        if let uploadLimit, uploadLimit > 0 {
            payloadSpeeches = Array(speeches.prefix(uploadLimit))
        } else {
            payloadSpeeches = speeches
        }
        let host = hostOverride ?? manifest.corpusId
        try await uploadPagesAndSegments(corpusId: manifest.corpusId,
                                         host: host,
                                         speeches: payloadSpeeches,
                                         pagePrefix: pagePrefix)
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

    private func uploadPagesAndSegments(
        corpusId: String,
        host: String,
        speeches: [FountainPlayParser.Speech],
        pagePrefix: String?
    ) async throws {
        var uploadedPages = Set<String>()

        for speech in speeches {
            let pageId = pageIdentifier(for: speech, prefix: pagePrefix)
            if uploadedPages.insert(pageId).inserted {
                let page = PersistServiceClient.PagePayload(
                    corpusId: corpusId,
                    pageId: pageId,
                    url: "\(host)://\(pageId)",
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

    private func pageIdentifier(for speech: FountainPlayParser.Speech, prefix: String?) -> String {
        let actValue = slugify(speech.act).nonEmptyOr("unknown")
        let sceneValue = slugify(speech.scene).nonEmptyOr("unknown")
        let base = "act-\(actValue)-scene-\(sceneValue)"
        if let p = prefix, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(p)/\(base)"
        }
        return base
    }

    private func segmentIdentifier(for speech: FountainPlayParser.Speech) -> String {
        "\(slugify(speech.speaker).nonEmptyOr("speaker"))-\(speech.index)"
    }

    private func pageTitle(for speech: FountainPlayParser.Speech) -> String {
        let act = speech.act.isEmpty ? "?" : speech.act
        let scene = speech.scene.isEmpty ? "?" : speech.scene
        let location = speech.location.isEmpty ? "" : " – \(speech.location)"
        return "Act \(act) Scene \(scene)\(location)"
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

private extension String {
    func nonEmptyOr(_ fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
