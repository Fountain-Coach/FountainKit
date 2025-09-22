import Foundation

public struct ToolManifest: Codable, Sendable {
    public struct Image: Codable, Sendable {
        public let name: String
        public let tarball: String
        public let sha256: String
        public let qcow2: String
        public let qcow2_sha256: String

        public init(name: String, tarball: String, sha256: String, qcow2: String, qcow2_sha256: String) {
            self.name = name
            self.tarball = tarball
            self.sha256 = sha256
            self.qcow2 = qcow2
            self.qcow2_sha256 = qcow2_sha256
        }
    }
    public let image: Image
    public let tools: [String: String]
    public let operations: [String]

    public init(image: Image, tools: [String: String], operations: [String]) {
        self.image = image
        self.tools = tools
        self.operations = operations
    }

    public static func load(from url: URL) throws -> ToolManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ToolManifest.self, from: data)
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
