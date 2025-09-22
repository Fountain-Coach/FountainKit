import Foundation

/// Root OpenAPI description loaded from specification files.
public struct OpenAPISpec: Codable {
    /// Reusable schema and security definitions.
    public struct Components: Codable {
        /// Map of schema names to definitions.
        public var schemas: [String: Schema]
        /// Optional authentication schemes keyed by name.
        public var securitySchemes: [String: SecurityScheme]?
    }

    /// Describes a server hosting the API.
    public struct Server: Codable {
        /// Base URL of the server.
        public var url: String
        /// Optional human readable description.
        public var description: String?
    }

    /// Authentication mechanism supported by the API.
    public struct SecurityScheme: Codable {
        /// Type of the scheme such as `http` or `apiKey`.
        public var type: String
        /// HTTP authentication scheme (e.g. `bearer`).
        public var scheme: String?
        /// Name of the header or query parameter carrying credentials.
        public var name: String?
        /// Location where the credential is transmitted.
        public var location: String?

        enum CodingKeys: String, CodingKey {
            case type, scheme, name
            case location = "in"
        }
    }

    /// Lists required security schemes for an operation.
    public struct SecurityRequirement: Codable {
        /// Mapping of scheme names to required scopes.
        public var schemes: [String: [String]]

        /// Creates a requirement with the given scheme map.
        public init(schemes: [String: [String]]) {
            self.schemes = schemes
        }

        /// Creates a requirement by decoding a simple dictionary.
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            schemes = try container.decode([String: [String]].self)
        }

        /// Encodes the requirement as a dictionary.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(schemes)
        }
    }

    /// Basic JSON Schema representation used throughout the spec.
    public final class Schema: Codable {
        public final class Property: Codable {
            public var ref: String?
            public var type: String?
            public var enumValues: [String]?
            public var items: Schema?
            public var allOf: [Schema]?
            public var oneOf: [Schema]?
            public var additionalProperties: Schema?

            enum CodingKeys: String, CodingKey {
                case ref = "$ref"
                case type
                case enumValues = "enum"
                case items
                case allOf
                case oneOf
                case additionalProperties
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                ref = try container.decodeIfPresent(String.self, forKey: .ref)
                type = try container.decodeIfPresent(String.self, forKey: .type)
                enumValues = try container.decodeIfPresent([String].self, forKey: .enumValues)
                items = try container.decodeIfPresent(Schema.self, forKey: .items)
                allOf = try container.decodeIfPresent([Schema].self, forKey: .allOf)
                oneOf = try container.decodeIfPresent([Schema].self, forKey: .oneOf)
                if let bool = try? container.decode(Bool.self, forKey: .additionalProperties) {
                    additionalProperties = bool ? Schema() : nil
                } else {
                    additionalProperties = try container.decodeIfPresent(Schema.self, forKey: .additionalProperties)
                }
            }

            public init() {}
        }

        public var ref: String?
        public var type: String?
        public var properties: [String: Property]?
        public var enumValues: [String]?
        public var items: Schema?
        public var allOf: [Schema]?
        public var oneOf: [Schema]?
        public var additionalProperties: Schema?

        enum CodingKeys: String, CodingKey {
            case ref = "$ref"
            case type
            case properties
            case enumValues = "enum"
            case items
            case allOf
            case oneOf
            case additionalProperties
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            ref = try container.decodeIfPresent(String.self, forKey: .ref)
            type = try container.decodeIfPresent(String.self, forKey: .type)
            properties = try container.decodeIfPresent([String: Property].self, forKey: .properties)
            enumValues = try container.decodeIfPresent([String].self, forKey: .enumValues)
            items = try container.decodeIfPresent(Schema.self, forKey: .items)
            allOf = try container.decodeIfPresent([Schema].self, forKey: .allOf)
            oneOf = try container.decodeIfPresent([Schema].self, forKey: .oneOf)
            if let bool = try? container.decode(Bool.self, forKey: .additionalProperties) {
                additionalProperties = bool ? Schema() : nil
            } else {
                additionalProperties = try container.decodeIfPresent(Schema.self, forKey: .additionalProperties)
            }
        }

        public init() {}
    }

    /// Parameter object representing path or query parameters.
    public struct Parameter: Codable {
        /// Original parameter name as declared in the specification.
        public var name: String
        /// Location where the parameter is supplied such as `path` or `query`.
        public var location: String
        /// Indicates whether the parameter must be present on requests.
        public var required: Bool?
        /// Schema describing the expected parameter data type.
        public var schema: Schema?

        enum CodingKeys: String, CodingKey {
            case name
            case location = "in"
            case required
            case schema
        }
    }

    /// Media type containing a schema.
    public struct MediaType: Codable {
        public var schema: Schema?
    }

    /// Request body container.
    public struct RequestBody: Codable {
        public var content: [String: MediaType]
    }

    /// Response object keyed by status code.
    public struct Response: Codable {
        public var description: String?
        public var content: [String: MediaType]?
    }

    /// Operation including parameters, request body and responses.
    public struct Operation: Codable {
        public var operationId: String
        public var parameters: [Parameter]?
        public var requestBody: RequestBody?
        public var responses: [String: Response]?
        public var security: [SecurityRequirement]?
    }

    /// Path item grouping multiple HTTP methods.
    public struct PathItem: Codable {
        public var get: Operation?
        public var post: Operation?
        public var put: Operation?
        public var delete: Operation?
    }

    public let title: String
    public var servers: [Server]?
    public var components: Components?
    public var paths: [String: PathItem]?
}

extension OpenAPISpec.Schema.Property {
    /// Returns the Swift type that best represents the property schema.
    /// Falls back to `String` when no explicit type information is available.
    public var swiftType: String {
        if let ref {
            return ref.components(separatedBy: "/").last ?? ref
        }
        // Composite schemas (`allOf`/`oneOf`) inherit the type of the first entry.
        if let first = allOf?.first ?? oneOf?.first {
            return first.swiftType
        }
        // Without an explicit type we default to `String`.
        guard let type else { return "String" }
        switch type {
        case "string": return "String"
        case "integer": return "Int"
        case "boolean": return "Bool"
        case "array":
            // Use the element's Swift type when provided, otherwise an array of strings.
            if let itemType = items?.swiftType {
                return "[\(itemType)]"
            } else {
                return "[String]"
            }
        case "object":
            // Represent JSON objects as dictionaries keyed by string.
            if let additional = additionalProperties {
                // When `additionalProperties` defines a schema, expose its Swift type.
                return "[String: \(additional.swiftType)]"
            }
            // Fallback to a simple string dictionary.
            return "[String: String]"
        default:
            // Any unknown schema types are treated as strings.
            return "String"
        }
    }
}

extension OpenAPISpec.Schema {
    /// Provides the Swift type represented by the schema itself.
    /// When referencing other schemas the last path component of the
    /// reference is used as the type name.
    public var swiftType: String {
        if let ref {
            return ref.components(separatedBy: "/").last ?? ref
        }
        if let first = allOf?.first ?? oneOf?.first {
            return first.swiftType
        }
        guard let type else { return "String" }
        switch type {
        case "string": return "String"
        case "integer": return "Int"
        case "boolean": return "Bool"
        case "array":
            if let itemType = items?.swiftType {
                return "[\(itemType)]"
            } else {
                return "[String]"
            }
        case "object":
            if let additional = additionalProperties {
                return "[String: \(additional.swiftType)]"
            }
            return "[String: String]"
        default: return "String"
        }
    }
}

extension OpenAPISpec.Parameter {
    /// Swift identifier-safe name for the parameter, replacing hyphens with underscores.
    public var swiftName: String {
        name.replacingOccurrences(of: "-", with: "_")
    }

    /// Swift type inferred from the associated schema, defaulting to `String` when unspecified.
    public var swiftType: String {
        schema?.swiftType ?? "String"
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
