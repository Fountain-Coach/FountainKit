import Foundation

public enum SeederError: Error, CustomStringConvertible, Sendable {
    case repoNotFound(String)
    case invalidStructure(String)
    case ioError(String)

    public var description: String {
        switch self {
        case .repoNotFound(let path):
            return "Repository not found at \(path)"
        case .invalidStructure(let message):
            return message
        case .ioError(let message):
            return message
        }
    }
}

public struct PersistenceSeeder {
    private let fileManager: FileManager
    private let parser: MarkdownParser
    private let hasher: FileHasher
    private let fountainParser: FountainPlayParser

    public init() {
        self.fileManager = .default
        self.parser = MarkdownParser()
        self.hasher = FileHasher()
        self.fountainParser = FountainPlayParser()
    }

    public func seed(
        repoPath: String,
        corpusId: String,
        sourceRepo: String,
        output: URL,
        playFilter: String? = nil
    ) throws -> SeedResult {
        let repoURL = URL(fileURLWithPath: repoPath, isDirectory: true)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: repoURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw SeederError.repoNotFound(repoURL.path)
        }

        var documents = try collectMarkdownEntries(root: repoURL, subdirectory: "texts", extraMetadata: ["type": "document"])
        let translations = try collectMarkdownEntries(root: repoURL, subdirectory: "translations", extraMetadata: ["type": "translation"])
        let annotations = try collectJSONEntries(root: repoURL, subdirectory: "annotations")
        let audio = try collectBinaryEntries(root: repoURL, subdirectory: "audio")

        let playURL = try resolveFountainCorpusURL(root: repoURL)
        let plays = try fountainParser.parseAllPlays(fileURL: playURL)
        let selectedPlays = try selectPlays(from: plays, filter: playFilter)
        guard !selectedPlays.isEmpty else {
            throw SeederError.invalidStructure("No plays available after applying filters.")
        }

        var derivedEntries: [SeedManifest.FileEntry] = []
        var allSpeeches: [FountainPlayParser.Speech] = []
        for play in selectedPlays {
            let entries = makeSpeechEntries(for: play.speeches, play: play)
            derivedEntries.append(contentsOf: entries)
            allSpeeches.append(contentsOf: play.speeches)
        }
        documents.append(contentsOf: derivedEntries)

        let manifest = SeedManifest(
            corpusId: corpusId,
            sourceRepo: sourceRepo,
            generatedAt: Date(),
            documents: documents,
            translations: translations,
            annotations: annotations,
            audio: audio
        )

        try writeManifest(manifest, to: output)
        return SeedResult(manifest: manifest, speeches: allSpeeches)
    }

    public func seedPlays(
        repoPath: String,
        corpusPrefix: String,
        sourceRepo: String,
        output: URL,
        playFilter: String? = nil
    ) throws -> [PlaySeedResult] {
        let repoURL = URL(fileURLWithPath: repoPath, isDirectory: true)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: repoURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw SeederError.repoNotFound(repoURL.path)
        }

        let playFileURL = try resolveFountainCorpusURL(root: repoURL)
        let plays = try fountainParser.parseAllPlays(fileURL: playFileURL)
        let selectedPlays = try selectPlays(from: plays, filter: playFilter)
        guard !selectedPlays.isEmpty else {
            throw SeederError.invalidStructure("No plays available after applying filters.")
        }

        var results: [PlaySeedResult] = []

        for play in selectedPlays {
            let corpusId = corpusPrefix.isEmpty ? play.slug : "\(corpusPrefix)-\(play.slug)"
            let entries = makeSpeechEntries(for: play.speeches, play: play)
            let manifest = SeedManifest(
                corpusId: corpusId,
                sourceRepo: sourceRepo,
                generatedAt: Date(),
                documents: entries,
                translations: [],
                annotations: [],
                audio: []
            )
            let result = SeedResult(manifest: manifest, speeches: play.speeches)
            let playOutput = output.appendingPathComponent(play.slug, isDirectory: true)
            try writeManifest(manifest, to: playOutput)
            results.append(PlaySeedResult(title: play.title, slug: play.slug, result: result))
        }

        return results
    }

    private func collectMarkdownEntries(root: URL, subdirectory: String, extraMetadata: [String:String]) throws -> [SeedManifest.FileEntry] {
        let dir = root.appendingPathComponent(subdirectory)
        guard fileManager.fileExists(atPath: dir.path) else {
            return []
        }
        let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var entries: [SeedManifest.FileEntry] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            let frontMatter = try parser.parse(fileURL: fileURL)
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let size = attributes[.size] as? NSNumber
            let sha = try hasher.sha256(for: fileURL)
            var metadata = extraMetadata
            frontMatter.metadata.forEach { key, value in
                if let string = value as? String {
                    metadata[key] = string
                } else {
                    metadata[key] = "\(value)"
                }
            }
            metadata["bodyLength"] = "\(frontMatter.body.count)"
            let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            entries.append(.init(path: relativePath, sha256: sha, size: size?.intValue ?? 0, metadata: metadata))
        }
        return entries.sorted { $0.path < $1.path }
    }

    private func collectJSONEntries(root: URL, subdirectory: String) throws -> [SeedManifest.FileEntry] {
        let dir = root.appendingPathComponent(subdirectory)
        guard fileManager.fileExists(atPath: dir.path) else { return [] }
        let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var entries: [SeedManifest.FileEntry] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension.lowercased() == "json" else { continue }
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let size = attributes[.size] as? NSNumber
            let sha = try hasher.sha256(for: fileURL)
            let metadata = ["type": "annotation"]
            let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            entries.append(.init(path: relativePath, sha256: sha, size: size?.intValue ?? 0, metadata: metadata))
        }
        return entries.sorted { $0.path < $1.path }
    }

    private func collectBinaryEntries(root: URL, subdirectory: String) throws -> [SeedManifest.FileEntry] {
        let dir = root.appendingPathComponent(subdirectory)
        guard fileManager.fileExists(atPath: dir.path) else { return [] }
        let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var entries: [SeedManifest.FileEntry] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.hasDirectoryPath == false else { continue }
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let size = attributes[.size] as? NSNumber
            let sha = try hasher.sha256(for: fileURL)
            var metadata: [String:String] = ["type": "artifact"]
            metadata["extension"] = fileURL.pathExtension
            let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            entries.append(.init(path: relativePath, sha256: sha, size: size?.intValue ?? 0, metadata: metadata))
        }
        return entries.sorted { $0.path < $1.path }
    }

    private func writeManifest(_ manifest: SeedManifest, to output: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        let fileURL = output.appendingPathComponent("seed-manifest.json")
        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private func makeSpeechEntries(for speeches: [FountainPlayParser.Speech], play: FountainPlayParser.Play) -> [SeedManifest.FileEntry] {
        speeches.map { speech -> SeedManifest.FileEntry in
            let text = speech.lines.joined(separator: "\n")
            let data = text.data(using: .utf8) ?? Data()
            var metadata: [String:String] = [
                "type": "speech",
                "act": speech.act,
                "scene": speech.scene,
                "location": speech.location,
                "speaker": speech.speaker,
                "index": String(speech.index),
                "play": play.slug,
                "playTitle": play.title
            ]
            metadata = metadata.filter { !$0.value.isEmpty }
            let actComponent = sanitizePathComponent(speech.act).nonEmptyOr("unknown")
            let sceneComponent = sanitizePathComponent(speech.scene).nonEmptyOr("unknown")
            let speakerComponent = sanitizePathComponent(speech.speaker).nonEmptyOr("speaker")
            let relativePath = "derived/\(play.slug)/act-\(actComponent)/scene-\(sceneComponent)/\(speakerComponent)-\(speech.index)"
            return SeedManifest.FileEntry(
                path: relativePath,
                sha256: hasher.sha256(data: data),
                size: data.count,
                metadata: metadata
            )
        }
    }

    private func locateTheFourStarsFile(root: URL) -> URL? {
        let candidates = ["the four stars.txt", "the four stars"]
        for name in candidates {
            let url = root.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private func resolveFountainCorpusURL(root: URL) throws -> URL {
        if let url = locateTheFourStarsFile(root: root) {
            return url
        }
        throw SeederError.invalidStructure("Could not find 'the four stars' source file")
    }

    private func selectPlays(from plays: [FountainPlayParser.Play], filter: String?) throws -> [FountainPlayParser.Play] {
        guard let filter, !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return plays
        }
        let normalized = sanitizePathComponent(filter)
        let exactMatches = plays.filter {
            sanitizePathComponent($0.slug) == normalized || sanitizePathComponent($0.title) == normalized
        }
        if !exactMatches.isEmpty {
            return exactMatches
        }
        let looseMatches = plays.filter { $0.title.localizedCaseInsensitiveContains(filter) }
        if !looseMatches.isEmpty {
            return looseMatches
        }
        throw SeederError.invalidStructure("Play named '\(filter)' not found in the corpus.")
    }

    private func sanitizePathComponent(_ value: String) -> String {
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
