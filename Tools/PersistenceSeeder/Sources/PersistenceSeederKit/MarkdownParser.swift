import Foundation
import Yams

struct MarkdownFrontMatter {
    let metadata: [String: Any]
    let body: String

    func stringValue(for key: String) -> String? {
        metadata[key] as? String
    }
}

enum MarkdownParserError: Error {
    case malformedFrontMatter
}

struct MarkdownParser {
    func parse(fileURL: URL) throws -> MarkdownFrontMatter {
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        guard text.hasPrefix("---\n") else {
            return MarkdownFrontMatter(metadata: [:], body: text)
        }
        guard let closingRange = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex) else {
            throw MarkdownParserError.malformedFrontMatter
        }
        let start = text.index(text.startIndex, offsetBy: 4)
        let frontMatter = String(text[start..<closingRange.lowerBound])
        let bodyStart = closingRange.upperBound
        let body = String(text[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let metadata = try Yams.load(yaml: frontMatter) as? [String: Any] ?? [:]
        return MarkdownFrontMatter(metadata: metadata, body: body)
    }
}
