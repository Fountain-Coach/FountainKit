import Foundation
import TeatroCore

public struct FountainPlayParser: Sendable {
    public struct Speech: Sendable, Equatable {
        public let act: String
        public let scene: String
        public let location: String
        public let speaker: String
        public let lines: [String]
        public let index: Int

        public init(act: String, scene: String, location: String, speaker: String, lines: [String], index: Int) {
            self.act = act
            self.scene = scene
            self.location = location
            self.speaker = speaker
            self.lines = lines
            self.index = index
        }
    }

    public struct Play: Sendable, Equatable {
        public let title: String
        public let slug: String
        public let speeches: [Speech]

        public init(title: String, slug: String, speeches: [Speech]) {
            self.title = title
            self.slug = slug
            self.speeches = speeches
        }
    }

    public enum ParserError: Error, CustomStringConvertible {
        case playNotFound(String)

        public var description: String {
            switch self {
            case .playNotFound(let name):
                return "Play named '\(name)' not found in source corpus."
            }
        }
    }

    public init() {}

    public func parseAllPlays(fileURL: URL) throws -> [Play] {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return try parseAllPlays(text: content)
    }

    public func parsePlay(named name: String, fileURL: URL) throws -> Play {
        let plays = try parseAllPlays(fileURL: fileURL)
        let normalized = slugify(name)
        if let exact = plays.first(where: { $0.slug == normalized }) {
            return exact
        }
        if let loose = plays.first(where: { $0.title.localizedCaseInsensitiveContains(name) }) {
            return loose
        }
        throw ParserError.playNotFound(name)
    }

    // MARK: - Internal parsing

    private func parseAllPlays(text: String) throws -> [Play] {
        let lines = text.components(separatedBy: "\n")
        let boundaries = detectPlayBoundaries(lines: lines)
        guard !boundaries.isEmpty else { return [] }

        var plays: [Play] = []
        let parser = FountainParser()
        for (index, boundary) in boundaries.enumerated() {
            let start = boundary.start
            let end = index + 1 < boundaries.count ? boundaries[index + 1].start : lines.count
            guard start < end else { continue }
            let slice = Array(lines[start..<end])
            let normalized = normalizePlayLines(slice)
            let nodes = parser.parse(normalized)
            let speeches = buildSpeeches(nodes: nodes)
            if speeches.isEmpty { continue }
            plays.append(Play(title: boundary.title, slug: slugify(boundary.title), speeches: speeches))
        }
        return plays
    }

    private struct PlayBoundary {
        let title: String
        let start: Int
    }

    private func detectPlayBoundaries(lines: [String]) -> [PlayBoundary] {
        var boundaries: [PlayBoundary] = []
        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                index += 1
                continue
            }
            if let nextIdx = nextNonEmptyIndex(after: index, in: lines) {
                let nextLine = lines[nextIdx].trimmingCharacters(in: .whitespacesAndNewlines)
                if nextLine.uppercased().hasPrefix("**** ACT") {
                    boundaries.append(PlayBoundary(title: line, start: index))
                }
            }
            index += 1
        }
        return boundaries
    }

    private func nextNonEmptyIndex(after position: Int, in lines: [String]) -> Int? {
        var idx = position + 1
        while idx < lines.count {
            if !lines[idx].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return idx
            }
            idx += 1
        }
        return nil
    }

    private func normalizePlayLines(_ rawLines: [String]) -> String {
        var normalized: [String] = []
        for (index, rawLine) in rawLines.enumerated() {
            // Skip the play title line; we rely on act/scene sections for structure.
            if index == 0 { continue }
            if let actLine = normalizeActLine(rawLine) {
                normalized.append(actLine)
                normalized.append("")
            } else if let sceneLine = normalizeSceneLine(rawLine) {
                normalized.append(sceneLine)
                normalized.append("")
            } else {
                normalized.append(rawLine)
            }
        }
        return normalized.joined(separator: "\n")
    }

    private func normalizeActLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("****"), trimmed.uppercased().contains("ACT") else { return nil }
        guard trimmed.hasSuffix("****") else { return nil }
        let inner = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "* ")).trimmingCharacters(in: .whitespacesAndNewlines)
        guard inner.uppercased().hasPrefix("ACT") else { return nil }
        return "# \(inner)"
    }

    private func normalizeSceneLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("****"), trimmed.uppercased().contains("SCENE") else { return nil }
        guard trimmed.hasSuffix("****") else { return nil }
        let inner = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "* ")).trimmingCharacters(in: .whitespacesAndNewlines)
        guard inner.uppercased().hasPrefix("SCENE") else { return nil }
        return "## \(inner)"
    }

    private func buildSpeeches(nodes: [FountainNode]) -> [Speech] {
        var speeches: [Speech] = []
        var currentAct: String = ""
        var currentScene: String = ""
        var currentLocation: String = ""
        var currentSpeaker: String?
        var buffer: [String] = []
        var speechIndex: Int = 0

        func flushCurrentSpeech() {
            guard let speaker = currentSpeaker else {
                buffer.removeAll()
                return
            }
            let lines = buffer.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !lines.isEmpty else {
                buffer.removeAll()
                currentSpeaker = nil
                return
            }
            speechIndex += 1
            let speech = Speech(
                act: currentAct,
                scene: currentScene,
                location: currentLocation,
                speaker: speaker,
                lines: lines,
                index: speechIndex
            )
            speeches.append(speech)
            buffer.removeAll()
            currentSpeaker = nil
        }

        for node in nodes {
            switch node.type {
            case .section(let level):
                flushCurrentSpeech()
                let descriptor = stripSections(from: node.rawText)
                if level == 1 {
                    currentAct = parseAct(descriptor)
                } else if level >= 2 {
                    let parsed = parseScene(descriptor)
                    if let scene = parsed.scene {
                        currentScene = scene
                    }
                    if let location = parsed.location {
                        currentLocation = location
                    }
                }
            case .sceneHeading:
                flushCurrentSpeech()
                let parsed = parseScene(node.rawText)
                if let scene = parsed.scene {
                    currentScene = scene
                }
                if let location = parsed.location {
                    currentLocation = location
                }
            case .character:
                flushCurrentSpeech()
                currentSpeaker = node.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            case .parenthetical, .dialogue:
                if currentSpeaker != nil {
                    buffer.append(node.rawText)
                }
            default:
                if currentSpeaker != nil {
                    flushCurrentSpeech()
                }
            }
        }

        flushCurrentSpeech()
        return speeches
    }

    private func stripSections(from raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix("#") {
            trimmed.removeFirst()
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseAct(_ descriptor: String) -> String {
        let trimmed = descriptor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.uppercased().hasPrefix("ACT") else { return trimmed }
        let remainder = trimmed.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
        return remainder.isEmpty ? trimmed : remainder
    }

    private func parseScene(_ descriptor: String) -> (scene: String?, location: String?) {
        let trimmed = descriptor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("scene") else {
            return (scene: nil, location: nil)
        }
        let afterScene = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !afterScene.isEmpty else { return (scene: nil, location: nil) }
        if let dotIndex = afterScene.firstIndex(of: ".") {
            let scenePart = afterScene[..<dotIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let locationPart = afterScene[afterScene.index(after: dotIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedLocation = stripTrailingPunctuation(locationPart)
            return (scene: scenePart, location: cleanedLocation.isEmpty ? nil : cleanedLocation)
        } else {
            return (scene: stripTrailingPunctuation(afterScene), location: nil)
        }
    }

    private func stripTrailingPunctuation(_ text: String) -> String {
        var trimmed = text
        while trimmed.hasSuffix(".") {
            trimmed.removeLast()
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func slugify(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        var lowercase = value.lowercased()
        lowercase = lowercase.replacingOccurrences(of: " ", with: "-")
        let mapped = lowercase.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        var slug = String(mapped)
        while slug.contains("--") {
            slug = slug.replacingOccurrences(of: "--", with: "-")
        }
        return slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
