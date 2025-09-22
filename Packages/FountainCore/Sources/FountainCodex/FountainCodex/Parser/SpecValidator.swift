import Foundation

/// Utility validating parsed ``OpenAPISpec`` models for common mistakes.
public enum SpecValidator {
    /// Error describing why a specification failed validation.
    public struct ValidationError: Error, Equatable, CustomStringConvertible {
        public let message: String
        public var description: String { message }

        public init(_ message: String) {
            self.message = message
        }
    }

    /// Performs a series of assertions to ensure the specification is usable.
    /// - Parameter spec: The specification model to verify.
    /// - Throws: ``ValidationError`` when the document contains inconsistencies.
    public static func validate(_ spec: OpenAPISpec) throws {
        if spec.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError("title cannot be empty")
        }

        /// Recursively verifies that referenced schemas exist within components.
        /// - Parameter schema: Schema to verify for unresolved references.
        func validateSchema(_ schema: OpenAPISpec.Schema) throws {
            if let ref = schema.ref {
                let name = ref.components(separatedBy: "/").last ?? ref
                if spec.components?.schemas[name] == nil {
                    throw ValidationError("unresolved reference \(ref)")
                }
            }
            if let properties = schema.properties {
                for property in properties.values {
                    if let ref = property.ref {
                        let name = ref.components(separatedBy: "/").last ?? ref
                        if spec.components?.schemas[name] == nil {
                            throw ValidationError("unresolved reference \(ref)")
                        }
                    }
                }
            }
        }

        if let components = spec.components {
            for schema in components.schemas.values {
                try validateSchema(schema)
            }
        }

        if let paths = spec.paths {
            var seenIds = Set<String>()
            for (path, item) in paths {
                let operations = [item.get, item.post, item.put, item.delete].compactMap { $0 }
                for op in operations {
                    if seenIds.contains(op.operationId) {
                        throw ValidationError("duplicate operationId \(op.operationId)")
                    }
                    seenIds.insert(op.operationId)
                    if op.operationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        throw ValidationError("operationId cannot be empty for \(path)")
                    }

                    for param in op.parameters ?? [] {
                        if param.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            throw ValidationError("parameter name cannot be empty in \(op.operationId)")
                        }
                        if param.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            throw ValidationError("parameter location cannot be empty in \(param.name)")
                        }
                        // Path parameters must always be marked as required.
                        if param.location == "path" && param.required != true {
                            throw ValidationError("path parameter \(param.name) must be required")
                        }
                        if let schema = param.schema {
                            try validateSchema(schema)
                        }
                    }

                    let segments = path.split(separator: "/")
                    for seg in segments where seg.hasPrefix("{") && seg.hasSuffix("}") {
                        let name = String(seg.dropFirst().dropLast())
                        // Ensure each placeholder segment has a matching path parameter.
                        let match = op.parameters?.first { $0.name == name && $0.location == "path" }
                        if match == nil {
                            throw ValidationError("missing parameter \(name) for path \(path)")
                        }
                    }

                    if let body = op.requestBody {
                        for media in body.content.values {
                            if let schema = media.schema {
                                try validateSchema(schema)
                            }
                        }
                    }

                    if let responses = op.responses {
                        for response in responses.values {
                            if let content = response.content {
                                for media in content.values {
                                    if let schema = media.schema {
                                        try validateSchema(schema)
                                    }
                                }
                            }
                        }
                    }

                    if let security = op.security {
                        for requirement in security {
                            for name in requirement.schemes.keys {
                                if spec.components?.securitySchemes?[name] == nil {
                                    throw ValidationError("unknown security scheme \(name)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
