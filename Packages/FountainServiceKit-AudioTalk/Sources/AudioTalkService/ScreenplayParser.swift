import Foundation

struct ParsedScreenplayResult: Sendable {
    let model: Components.Schemas.ScreenplayModel
    let warnings: [String]
}

enum ScreenplayParser {
    static func parse(id: String, text: String) -> ParsedScreenplayResult {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" })
        var sceneNumber = 0
        var scenes: [Components.Schemas.ScreenplayModel.scenesPayloadPayload] = []
        var beats: [Components.Schemas.ScreenplayModel.beatsPayloadPayload] = []
        var notes: [Components.Schemas.ScreenplayModel.notesPayloadPayload] = []
        var characters: Set<String> = []
        var warnings: [String] = []

        func isSceneHeading(_ s: Substring) -> Bool {
            let str = s.trimmingCharacters(in: .whitespaces)
            if str.isEmpty { return false }
            let prefixes = ["INT.", "EXT.", "INT/EXT.", "I/E.", "EST."]
            return prefixes.contains { str.hasPrefix($0) }
        }

        func isSynopsis(_ s: Substring) -> Bool {
            s.trimmingCharacters(in: .whitespaces).hasPrefix("=")
        }

        func findInlineTags(_ s: Substring) -> [String] {
            // [[AudioTalk: ...]]
            var out: [String] = []
            var str = String(s)
            while let start = str.range(of: "[[AudioTalk:") {
                guard let end = str.range(of: "]]", range: start.upperBound..<str.endIndex) else { break }
                let content = str[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespaces)
                out.append(content)
                str.removeSubrange(start.lowerBound..<end.upperBound)
            }
            return out
        }

        var currentSceneId: String? = nil

        for (i, raw) in lines.enumerated() {
            let lineNo = i + 1
            let s = raw
            let trimmed = s.trimmingCharacters(in: .whitespaces)

            if isSceneHeading(s) {
                sceneNumber += 1
                currentSceneId = "sc\(sceneNumber)"
                scenes.append(.init(id: currentSceneId!, number: sceneNumber, heading: String(trimmed), page_start: nil, page_end: nil))
                continue
            }

            if isSynopsis(s) {
                if let sc = currentSceneId {
                    let summary = String(trimmed.dropFirst().trimmingCharacters(in: .whitespaces))
                    beats.append(.init(id: "bt\(sceneNumber)_\(lineNo)", scene_id: sc, summary: summary, page: nil, line: lineNo))
                } else {
                    warnings.append("Synopsis without scene at line \(lineNo)")
                }
            }

            // Character lines (simple heuristic: ALL CAPS words, centered)
            if trimmed == trimmed.uppercased(), trimmed.count > 1, trimmed.rangeOfCharacter(from: CharacterSet.letters) != nil, !trimmed.hasPrefix("#") {
                characters.insert(trimmed)
            }

            let tags = findInlineTags(s)
            for t in tags {
                let anchor = Components.Schemas.ScriptAnchor(scene_number: sceneNumber > 0 ? sceneNumber : nil, page: nil, line: lineNo, character: nil)
                notes.append(.init(id: "nt\(sceneNumber)_\(lineNo)", kind: .tag, content: t, anchor: anchor))
            }
        }

        let charList: [Components.Schemas.ScreenplayModel.charactersPayloadPayload] = characters.map { name in
            .init(name: name, aliases: nil)
        }

        let model = Components.Schemas.ScreenplayModel(
            scenes: scenes,
            beats: beats,
            notes: notes,
            characters: charList,
            arcs: []
        )
        return ParsedScreenplayResult(model: model, warnings: warnings)
    }
}

