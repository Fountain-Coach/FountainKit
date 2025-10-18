import Foundation

struct TextCompare: Sendable {
    static func normalizeForTokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { tokens.append(current.lowercased()); current.removeAll(keepingCapacity: true) }
        }
        for ch in text {
            if ch.isLetter || ch.isNumber || ch == "'" { current.unicodeScalars.append(contentsOf: String(ch).unicodeScalars) }
            else { flush() }
        }
        flush()
        return tokens
    }

    static func jaccard<T: Hashable>(_ a: Set<T>, _ b: Set<T>) -> Double {
        if a.isEmpty && b.isEmpty { return 1.0 }
        let inter = a.intersection(b).count
        let union = a.union(b).count
        return union == 0 ? 0.0 : Double(inter) / Double(union)
    }

    static func shingles(tokens: [String], size: Int) -> Set<String> {
        guard size > 0, tokens.count >= size else { return [] }
        var out = Set<String>()
        for i in 0...(tokens.count - size) {
            let s = tokens[i..<(i+size)].joined(separator: " ")
            out.insert(s)
        }
        return out
    }

    static func collapseWhitespace(_ s: String) -> String {
        var out = String()
        out.reserveCapacity(s.count)
        var inSpace = false
        for ch in s {
            if ch.isWhitespace {
                if !inSpace { out.append(" "); inSpace = true }
            } else {
                out.append(ch)
                inSpace = false
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizeForLines(_ s: String) -> [String] {
        return s
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { collapseWhitespace($0).lowercased() }
            .filter { !$0.isEmpty }
    }

    static func coverage(edition: String, canonical: String, minLineLen: Int) -> (coverage: Double, missingFromEdition: [String], addedInEdition: [String]) {
        // Normalise to comparable strings
        let canonNorm = collapseWhitespace(canonical.lowercased())
        let editionNorm = collapseWhitespace(edition.lowercased())

        func filterLines(_ lines: [String]) -> [String] {
            lines.filter { $0.count >= minLineLen }
        }

        let eLines = filterLines(normalizeForLines(edition))
        let cLines = filterLines(normalizeForLines(canonical))

        var present = 0
        var added: [String] = []
        for line in eLines {
            if canonNorm.contains(line) { present += 1 } else { added.append(line) }
        }
        var missing: [String] = []
        for line in cLines {
            if !editionNorm.contains(line) { missing.append(line) }
        }
        let cov = eLines.isEmpty ? 0.0 : Double(present) / Double(eLines.count)
        return (cov, missing, added)
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.

