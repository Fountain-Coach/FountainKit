import Foundation

public struct HTMLParser: Sendable {

    public init() {}

    public struct BlockSpan: Sendable {
        public let id: String
        public let kind: String
        public let level: Int?
        public let text: String
        public let start: Int
        public let end: Int
        public let table: SemanticMemoryService.FullAnalysis.Table?
    }

    public func parseTextAndBlocks(from html: String) -> (text: String, blocks: [BlockSpan]) {
        let stripped = stripScriptsAndStyles(html)
        var i = stripped.startIndex
        var out = String()
        var blocks: [BlockSpan] = []
        var nextHeading = 0, nextPara = 0, nextCode = 0, nextTable = 0

        while i < stripped.endIndex {
            if stripped[i] == "<" {
                if let gt = stripped[i...].firstIndex(of: ">") {
                    let raw = String(stripped[stripped.index(after: i)..<gt]).lowercased()
                    if let m = raw.firstMatch(of: /^h([1-6])\b/), let lvl = Int(String(m.1)) {
                        if let endTag = findClosingTag(in: stripped, from: gt, tag: "h\(lvl)") {
                            let inner = String(stripped[stripped.index(after: gt)..<endTag])
                            let text = normalizeSpaces(inner.removingHTMLTags()).trimmingCharacters(in: .whitespaces)
                            let start = out.count
                            if !text.isEmpty { out += (start == 0 ? "" : " ") + text }
                            let end = out.count
                            blocks.append(BlockSpan(id: "h\(nextHeading)", kind: "heading", level: lvl, text: text, start: start, end: end, table: nil))
                            nextHeading += 1
                            i = stripped.index(endTag, offsetBy: 4)
                            continue
                        }
                    } else if raw.hasPrefix("p") {
                        if let endTag = findClosingTag(in: stripped, from: gt, tag: "p") {
                            let inner = String(stripped[stripped.index(after: gt)..<endTag])
                            let text = normalizeSpaces(inner.removingHTMLTags()).trimmingCharacters(in: .whitespaces)
                            let start = out.count
                            if !text.isEmpty { out += (start == 0 ? "" : " ") + text }
                            let end = out.count
                            blocks.append(BlockSpan(id: "p\(nextPara)", kind: "paragraph", level: nil, text: text, start: start, end: end, table: nil))
                            nextPara += 1
                            i = stripped.index(endTag, offsetBy: 4)
                            continue
                        }
                    } else if raw.hasPrefix("pre") || raw.hasPrefix("code") {
                        let tag = raw.hasPrefix("pre") ? "pre" : "code"
                        if let endTag = findClosingTag(in: stripped, from: gt, tag: tag) {
                            let inner = String(stripped[stripped.index(after: gt)..<endTag])
                            let text = normalizeSpaces(inner.removingHTMLTags()).trimmingCharacters(in: .whitespaces)
                            let start = out.count
                            if !text.isEmpty { out += (start == 0 ? "" : " ") + text }
                            let end = out.count
                            blocks.append(BlockSpan(id: "c\(nextCode)", kind: "code", level: nil, text: text, start: start, end: end, table: nil))
                            nextCode += 1
                            i = stripped.index(endTag, offsetBy: 7)
                            continue
                        }
                    } else if raw.hasPrefix("table") {
                        if let endTag = findClosingTag(in: stripped, from: gt, tag: "table") {
                            let tableHTML = String(stripped[stripped.index(after: gt)..<endTag])
                            let caption = firstMatch(tableHTML, pattern: "<caption[^>]*>(.*?)</caption>")?.removingHTMLTags()
                            var columns: [String]? = nil
                            if let thead = firstMatch(tableHTML, pattern: "<thead[\\s\\S]*?</thead>") {
                                let ths = allMatches(thead, pattern: "<th[^>]*>(.*?)</th>").map { $0.removingHTMLTags() }
                                columns = ths.isEmpty ? nil : ths
                            }
                            let rowHTMLs = allMatches(tableHTML, pattern: "<tr[\\s\\S]*?</tr>")
                            var rows: [[String]] = []
                            for r in rowHTMLs {
                                let cells = allMatches(r, pattern: "<t[dh][^>]*>(.*?)</t[dh]>").map { $0.removingHTMLTags() }
                                if !cells.isEmpty { rows.append(cells) }
                            }
                            let table = SemanticMemoryService.FullAnalysis.Table(caption: caption, columns: columns, rows: rows)
                            let flat = (columns ?? []).joined(separator: " ") + " " + rows.prefix(3).flatMap { $0 }.joined(separator: " ")
                            let text = normalizeSpaces(flat).trimmingCharacters(in: .whitespaces)
                            let start = out.count
                            if !text.isEmpty { out += (start == 0 ? "" : " ") + text }
                            let end = out.count
                            blocks.append(BlockSpan(id: "t\(nextTable)", kind: "table", level: nil, text: text, start: start, end: end, table: table))
                            nextTable += 1
                            i = stripped.index(endTag, offsetBy: 8)
                            continue
                        }
                    }
                    i = stripped.index(after: gt)
                } else {
                    i = stripped.index(after: i)
                }
            } else {
                let nextLt = stripped[i...].firstIndex(of: "<") ?? stripped.endIndex
                let chunk = String(stripped[i..<nextLt])
                let nt = normalizeSpaces(chunk).trimmingCharacters(in: .whitespaces)
                if !nt.isEmpty { out += (out.isEmpty ? "" : " ") + nt }
                i = nextLt
            }
        }
        if blocks.isEmpty {
            return buildPlainTextBlocks(from: stripped)
        }
        return (out.trimmingCharacters(in: .whitespaces), blocks)
    }

    public func parseBlocks(from html: String) -> [SemanticMemoryService.FullAnalysis.Block] {
        let (_, spans) = parseTextAndBlocks(from: html)
        return spans.map { SemanticMemoryService.FullAnalysis.Block(id: $0.id, kind: $0.kind, text: $0.text, table: $0.table) }
    }

    // MARK: - Regex helpers
    private func matchesTwoGroups(_ s: String, pattern: String) -> [(String, String)] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return re.matches(in: s, options: [], range: range).compactMap { m in
            guard m.numberOfRanges >= 3,
                  let r1 = Range(m.range(at: 1), in: s),
                  let r2 = Range(m.range(at: 2), in: s) else { return nil }
            return (String(s[r1]), String(s[r2]))
        }
    }

    private func matchesOneGroup(_ s: String, pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return re.matches(in: s, options: [], range: range).compactMap { m in
            guard m.numberOfRanges >= 2, let r1 = Range(m.range(at: 1), in: s) else { return nil }
            return String(s[r1])
        }
    }

    private func allMatches(_ s: String, pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return re.matches(in: s, options: [], range: range).compactMap { m in
            guard let r = Range(m.range(at: 0), in: s) else { return nil }
            return String(s[r])
        }
    }

    private func firstMatch(_ s: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let m = re.firstMatch(in: s, options: [], range: range), m.numberOfRanges >= 2, let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    private func stripScriptsAndStyles(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: "", options: .regularExpression)
        return s
    }

    private func normalizeSpaces(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "&nbsp;", with: " ")
        t = t.replacingOccurrences(of: "&amp;", with: "&")
        t = t.replacingOccurrences(of: "&lt;", with: "<")
        t = t.replacingOccurrences(of: "&gt;", with: ">")
        t = t.replacingOccurrences(of: "\r|\n|\t", with: " ", options: .regularExpression)
        return t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func looksLikeSpeakerLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 120 else { return false }
        guard trimmed.rangeOfCharacter(from: CharacterSet.letters) != nil else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,'’-:()\"/")
        return trimmed == trimmed.uppercased() && trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func buildPlainTextBlocks(from raw: String) -> (String, [BlockSpan]) {
        let collapsed = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = collapsed.components(separatedBy: "\n")
        var collectedText = ""
        var blocks: [BlockSpan] = []
        var paragraphCounter = 0
        var speechCounter = 0
        var currentLines: [String] = []
        var currentSpeaker: String? = nil

        func addBlock(text: String, identifier: String) {
            let cleaned = normalizeSpaces(text).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return }
            let start = collectedText.count
            if start > 0 { collectedText.append(" ") }
            collectedText.append(cleaned)
            let end = collectedText.count
            blocks.append(BlockSpan(id: identifier, kind: "paragraph", level: nil, text: cleaned, start: start, end: end, table: nil))
        }

        func flushCurrent() {
            defer {
                currentLines.removeAll(keepingCapacity: true)
                currentSpeaker = nil
            }
            if currentLines.isEmpty {
                if let speaker = currentSpeaker {
                    addBlock(text: speaker, identifier: "speaker\(speechCounter)")
                    speechCounter += 1
                }
                return
            }
            let body = currentLines.map { normalizeSpaces($0) }.joined(separator: " ")
            if let speaker = currentSpeaker {
                addBlock(text: "\(speaker): \(body)", identifier: "speech\(speechCounter)")
                speechCounter += 1
            } else {
                addBlock(text: body, identifier: "pPlain\(paragraphCounter)")
                paragraphCounter += 1
            }
        }

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushCurrent()
                continue
            }
            if looksLikeSpeakerLine(trimmed) {
                flushCurrent()
                currentSpeaker = trimmed
            } else {
                currentLines.append(trimmed)
            }
        }
        flushCurrent()

        if blocks.isEmpty {
            let text = normalizeSpaces(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                return ("", [])
            }
            return (text, [BlockSpan(id: "p0", kind: "paragraph", level: nil, text: text, start: 0, end: text.count, table: nil)])
        }
        return (collectedText, blocks)
    }

    private func findClosingTag(in s: String, from: String.Index, tag: String) -> String.Index? {
        let close = "</\(tag)>"
        return s[from...].range(of: close, options: .caseInsensitive)?.lowerBound
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
