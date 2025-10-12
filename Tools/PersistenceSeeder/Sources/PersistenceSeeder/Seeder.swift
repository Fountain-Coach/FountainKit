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

    func seed(repoPath: String, corpusId: String, sourceRepo: String, output: URL) throws -> SeedManifest {
        let repoURL = URL(fileURLWithPath: repoPath, isDirectory: true)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: repoURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw SeederError.repoNotFound(repoURL.path)
        }

        let documents = try collectMarkdownEntries(root: repoURL, subdirectory: "texts", extraMetadata: ["type": "document"])
        let translations = try collectMarkdownEntries(root: repoURL, subdirectory: "translations", extraMetadata: ["type": "translation"])
        let annotations = try collectJSONEntries(root: repoURL, subdirectory: "annotations")
        let audio = try collectBinaryEntries(root: repoURL, subdirectory: "audio")

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
        return manifest
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
}
