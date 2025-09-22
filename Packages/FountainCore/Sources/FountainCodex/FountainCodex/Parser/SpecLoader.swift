import Foundation
import Yams

/// Parses an OpenAPI specification from JSON or YAML.
public enum SpecLoader {
    /// Reads and validates a specification file.
    /// Strips copyright lines prefixed with "©" before decoding.
    /// - Parameter url: Location of the spec on disk.
    /// - Returns: Parsed ``OpenAPISpec`` instance.
    public static func load(from url: URL) throws -> OpenAPISpec {
        let data = try Data(contentsOf: url)
        var sanitizedData = data
        if let text = String(data: data, encoding: .utf8) {
            let filtered = text
                .split(separator: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("©") }
                .joined(separator: "\n")
            sanitizedData = Data(filtered.utf8)
        }

        // Attempt JSON decoding first. Successful parses are validated and
        // returned immediately. Any failure falls through to YAML handling.
        if let spec = try? JSONDecoder().decode(OpenAPISpec.self, from: sanitizedData) {
            try SpecValidator.validate(spec)
            return spec
        }

        // Fallback to YAML decoding when JSON parsing fails.
        // Non-UTF8 data or empty YAML documents produce explicit errors.
        guard let yamlString = String(data: sanitizedData, encoding: .utf8) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Input data is not valid UTF-8"))
        }
        guard let loadedYaml = try Yams.load(yaml: yamlString) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "YAML document is empty")
            )
        }
        var yamlObject = loadedYaml

        // If using OpenAPI 3.x with `info.title`, normalize to a top-level `title`.
        if var dict = yamlObject as? [String: Any] {
            if dict["title"] == nil,
               let info = dict["info"] as? [String: Any],
               let title = info["title"] {
                dict["title"] = title
            }
            yamlObject = dict
        }

        // Convert the YAML representation into JSON data for decoding.
        let jsonData = try JSONSerialization.data(withJSONObject: yamlObject, options: [])
        let spec = try JSONDecoder().decode(OpenAPISpec.self, from: jsonData)
        try SpecValidator.validate(spec)
        return spec
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
