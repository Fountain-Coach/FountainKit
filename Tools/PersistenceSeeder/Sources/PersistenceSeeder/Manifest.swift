import Foundation

struct SeedManifest: Codable, Equatable {
    struct FileEntry: Codable, Equatable {
        let path: String
        let sha256: String
        let size: Int
        let metadata: [String: String]
    }

    let corpusId: String
    let sourceRepo: String
    let generatedAt: Date
    let documents: [FileEntry]
    let translations: [FileEntry]
    let annotations: [FileEntry]
    let audio: [FileEntry]
}
