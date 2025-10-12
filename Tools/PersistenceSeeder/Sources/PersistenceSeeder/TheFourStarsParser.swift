import Foundation

struct TheFourStarsParser {
    struct Speech {
        let act: String
        let scene: String
        let location: String
        let speaker: String
        let lines: [String]
        let index: Int
    }

    func parse(fileURL: URL) throws -> [Speech] {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\r" || $0 == "\n" })
        var speeches: [Speech] = []
        var act = ""
        var scene = ""
        var location = ""
        var buffer: [String] = []
        var speaker: String = ""
        var speechIndex = 0

        func flush() {
            guard !speaker.isEmpty, !buffer.isEmpty else { return }
            speechIndex += 1
            let trimmedLines = buffer.map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }.filter { !$0.isEmpty }
            guard !trimmedLines.isEmpty else { return }
            speeches.append(Speech(act: act, scene: scene, location: location, speaker: speaker, lines: trimmedLines, index: speechIndex))
            buffer.removeAll(keepingCapacity: true)
        }

        let actRegex = try! NSRegularExpression(pattern: "\\*{4}\\s*ACT\\s+([IVXLC]+)\\s*\\*{4}", options: .caseInsensitive)
        let sceneRegex = try! NSRegularExpression(pattern: "\\*{4}\\s*SCENE\\s+([^\\*]+)\\*{4}", options: .caseInsensitive)

        for rawLine in lines {
            let line = String(rawLine)
            if line.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty {
                flush()
                speaker = ""
                continue
            }

            if let match = actRegex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)) {
                flush()
                if let range = Range(match.range(at: 1), in: line) {
                    act = line[range].trimmingCharacters(in: CharacterSet.whitespaces)
                }
                continue
            }

            if let match = sceneRegex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)) {
                flush()
                if let range = Range(match.range(at: 1), in: line) {
                    let sceneText = line[range].trimmingCharacters(in: CharacterSet.whitespaces)
                    let parts = sceneText.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
                    scene = parts.first.map { $0.trimmingCharacters(in: CharacterSet.whitespaces) } ?? sceneText
                    location = parts.dropFirst().first.map { $0.trimmingCharacters(in: CharacterSet.whitespaces) } ?? ""
                }
                continue
            }

            if isSpeakerLine(line) {
                flush()
                speaker = line.trimmingCharacters(in: CharacterSet.whitespaces)
                buffer.removeAll(keepingCapacity: true)
                continue
            }

            buffer.append(line)
        }
        flush()
        return speeches
    }

    private func isSpeakerLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces)
        guard !trimmed.isEmpty else { return false }
        guard trimmed == trimmed.uppercased() else { return false }
        // ignore lines that look like stage directions in brackets
        guard trimmed.first?.isLetter == true else { return false }
        return trimmed.rangeOfCharacter(from: CharacterSet.letters) != nil
    }
}
