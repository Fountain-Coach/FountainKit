import Foundation

public struct ManifestSummaryFormatter {
    private let snippetLimit: Int

    public init(snippetLimit: Int = 120) {
        self.snippetLimit = snippetLimit
    }

    public func format(result: SeedResult, header: String = "Seed Summary") -> String {
        let manifest = result.manifest
        var lines: [String] = []
        lines.append("===== \(header) =====")
        lines.append("Corpus: \(manifest.corpusId) (source: \(manifest.sourceRepo))")
        lines.append("Generated At: \(iso8601String(from: manifest.generatedAt))")
        lines.append("Documents: \(manifest.documents.count)")
        lines.append("Translations: \(manifest.translations.count)")
        lines.append("Annotations: \(manifest.annotations.count)")
        lines.append("Audio: \(manifest.audio.count)")
        lines.append("Derived Speeches: \(result.speeches.count)")
        if let sample = result.speeches.first {
            let snippet = sample.lines.joined(separator: " ")
            let suffix = snippet.count > snippetLimit ? "…" : ""
            let prefix = snippet.prefix(snippetLimit)
            lines.append("Sample: [\(sample.speaker)] Act \(sample.act) Scene \(sample.scene) – \(prefix)\(suffix)")
        }
        return lines.joined(separator: "\n")
    }

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
