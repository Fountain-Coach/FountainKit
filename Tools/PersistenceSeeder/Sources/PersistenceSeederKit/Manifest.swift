import Foundation

public struct SeedManifest: Codable, Equatable, Sendable {
    public struct FileEntry: Codable, Equatable, Sendable {
        public let path: String
        public let sha256: String
        public let size: Int
        public let metadata: [String: String]

        public init(path: String, sha256: String, size: Int, metadata: [String: String]) {
            self.path = path
            self.sha256 = sha256
            self.size = size
            self.metadata = metadata
        }
    }

    public let corpusId: String
    public let sourceRepo: String
    public let generatedAt: Date
    public let documents: [FileEntry]
    public let translations: [FileEntry]
    public let annotations: [FileEntry]
    public let audio: [FileEntry]

    public init(
        corpusId: String,
        sourceRepo: String,
        generatedAt: Date,
        documents: [FileEntry],
        translations: [FileEntry],
        annotations: [FileEntry],
        audio: [FileEntry]
    ) {
        self.corpusId = corpusId
        self.sourceRepo = sourceRepo
        self.generatedAt = generatedAt
        self.documents = documents
        self.translations = translations
        self.annotations = annotations
        self.audio = audio
    }
}

public struct SeedResult: Sendable {
    public let manifest: SeedManifest
    public let speeches: [FountainPlayParser.Speech]

    public init(manifest: SeedManifest, speeches: [FountainPlayParser.Speech]) {
        self.manifest = manifest
        self.speeches = speeches
    }
}

public struct PlaySeedResult: Sendable {
    public let title: String
    public let slug: String
    public let result: SeedResult

    public init(title: String, slug: String, result: SeedResult) {
        self.title = title
        self.slug = slug
        self.result = result
    }
}
