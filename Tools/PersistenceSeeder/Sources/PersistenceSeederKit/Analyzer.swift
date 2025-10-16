import Foundation
import Yams

public struct RepositoryProfile: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let path: String
        public let kind: String
        public let extensionName: String
        public let frontMatterKeys: [String]

        public init(path: String, kind: String, extensionName: String, frontMatterKeys: [String]) {
            self.path = path
            self.kind = kind
            self.extensionName = extensionName
            self.frontMatterKeys = frontMatterKeys
        }
    }

    public let totalFiles: Int
    public let extensions: [String: Int]
    public let directories: [String: Int]
    public let samples: [Entry]

    public init(totalFiles: Int, extensions: [String: Int], directories: [String: Int], samples: [Entry]) {
        self.totalFiles = totalFiles
        self.extensions = extensions
        self.directories = directories
        self.samples = samples
    }
}

public struct RepositoryAnalyzer {
    private let fileManager = FileManager.default
    private let parser = MarkdownParser()

    public init() {}

    public func analyze(repoPath: String, maxSamples: Int = 10) throws -> RepositoryProfile {
        let root = URL(fileURLWithPath: repoPath, isDirectory: true)
        guard fileManager.fileExists(atPath: root.path, isDirectory: nil) else {
            throw SeederError.repoNotFound(repoPath)
        }

        var totalFiles = 0
        var extensionCounts: [String: Int] = [:]
        var directoryCounts: [String: Int] = [:]
        var samples: [RepositoryProfile.Entry] = []

        let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        while let fileURL = enumerator?.nextObject() as? URL {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue else {
                continue
            }
            totalFiles += 1
            let ext = fileURL.pathExtension.lowercased()
            extensionCounts[ext, default: 0] += 1

            let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            if let dirName = relativePath.split(separator: "/").first {
                directoryCounts[String(dirName), default: 0] += 1
            }

            if samples.count < maxSamples {
                let kind = classify(extension: ext)
                var keys: [String] = []
                if ext == "md" {
                    if let frontMatter = try? parser.parse(fileURL: fileURL) {
                        keys = frontMatter.metadata.keys.map { String(describing: $0) }.sorted()
                    }
                } else if ext == "yml" || ext == "yaml" {
                    if let data = try? String(contentsOf: fileURL, encoding: .utf8),
                       let loaded = try? Yams.load(yaml: data) as? [String: Any] {
                        keys = loaded.keys.map { String(describing: $0) }.sorted()
                    }
                }
                samples.append(.init(path: relativePath, kind: kind, extensionName: ext, frontMatterKeys: keys))
            }
        }

        return RepositoryProfile(
            totalFiles: totalFiles,
            extensions: extensionCounts.sorted { $0.key < $1.key }.reduce(into: [:]) { $0[$1.key] = $1.value },
            directories: directoryCounts.sorted { $0.key < $1.key }.reduce(into: [:]) { $0[$1.key] = $1.value },
            samples: samples
        )
    }

    private func classify(extension ext: String) -> String {
        switch ext {
        case "md": return "markdown"
        case "json": return "json"
        case "mid", "midi": return "midi"
        case "yaml", "yml": return "yaml"
        default: return "binary"
        }
    }
}
