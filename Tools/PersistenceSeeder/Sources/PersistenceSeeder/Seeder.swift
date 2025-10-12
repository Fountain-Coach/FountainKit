import Foundation

enum SeederError: Error, CustomStringConvertible {
    case repoNotFound(String)
    case invalidStructure(String)
    case ioError(String)

    var description: String {
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

struct PersistenceSeeder {
    let fileManager = FileManager.default
    let parser = MarkdownParser()
    let hasher = FileHasher()

    func seed(repoPath: String, corpusId: String, sourceRepo: String, output: URL) throws -> SeedResult {
        let repoURL = URL(fileURLWithPath: repoPath, isDirectory: true)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: repoURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw SeederError.repoNotFound(repoURL.path)
        }

        var documents = try collectMarkdownEntries(root: repoURL, subdirectory: "texts", extraMetadata: ["type": "document"])
        let translations = try collectMarkdownEntries(root: repoURL, subdirectory: "translations", extraMetadata: ["type": "translation"])
        let annotations = try collectJSONEntries(root: repoURL, subdirectory: "annotations")
        let audio = try collectBinaryEntries(root: repoURL, subdirectory: "audio")

        let derived = try collectTheFourStarsSpeeches(root: repoURL)
        documents.append(contentsOf: derived.entries)

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
        return SeedResult(manifest: manifest, speeches: derived.speeches)
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

    private func collectTheFourStarsSpeeches(root: URL) throws -> (entries: [SeedManifest.FileEntry], speeches: [TheFourStarsParser.Speech]) {
        let playURL = root.appendingPathComponent("the four stars.txt")
        guard FileManager.default.fileExists(atPath: playURL.path) else { return ([], []) }
        let parser = TheFourStarsParser()
        let speeches = try parser.parse(fileURL: playURL)
        let entries = speeches.map { speech -> SeedManifest.FileEntry in
            let text = speech.lines.joined(separator: "\n")
            let data = text.data(using: .utf8) ?? Data()
            var metadata: [String:String] = [
                "type": "speech",
                "act": speech.act,
                "scene": speech.scene,
                "location": speech.location,
                "speaker": speech.speaker,
                "index": String(speech.index)
            ]
            metadata = metadata.filter { !$0.value.isEmpty }
            let relativePath = "derived/the-four-stars/act-\(sanitizePathComponent(speech.act))/scene-\(sanitizePathComponent(speech.scene))/\(sanitizePathComponent(speech.speaker))-\(speech.index)"
            return SeedManifest.FileEntry(
                path: relativePath,
                sha256: hasher.sha256(data: data),
                size: data.count,
                metadata: metadata
            )
        }
        return (entries, speeches)
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

    private func sanitizePathComponent(_ value: String) -> String {
        let lowered = value.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        var cleaned = lowered.replacingOccurrences(of: " ", with: "-")
        cleaned = cleaned.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }.map(String.init).joined()
        cleaned = cleaned.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
