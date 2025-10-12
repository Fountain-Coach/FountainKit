import Foundation
import Yams

struct ArcSpecCompiler {
    struct ArcSpec: Decodable {
        let arc: String
        let version: VersionValue
        let corpus: Corpus?
        let resources: [Resource]
        let operators: [Operator]
        let policies: Policies?
    }

    struct VersionValue: Decodable {
        let value: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let doubleValue = try? container.decode(Double.self) {
                value = String(doubleValue)
            } else if let intValue = try? container.decode(Int.self) {
                value = String(intValue)
            } else {
                value = try container.decode(String.self)
            }
        }
    }

    struct Corpus: Decodable {
        let id: String
        let refs: [CorpusRef]?
    }

    struct CorpusRef: Decodable {
        let type: String
        let url: String
    }

    struct Resource: Decodable {
        let id: String
        let kind: String
        let facets: [String]?
    }

    struct Operator: Decodable {
        struct Input: Decodable {
            enum CodingKeys: String, CodingKey {
                case name
                case type
                case required
                case defaultValue = "default"
            }

            let name: String
            let type: String
            let required: Bool?
            let defaultValue: DefaultValue?
        }

        struct Output: Decodable {
            enum CodingKeys: String, CodingKey {
                case type
                case guarantees
            }

            let type: String
            let guarantees: [String]?
        }

        let id: String
        let intent: String
        let input: [Input]
        let output: Output
    }

    enum DefaultValue: Decodable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let boolValue = try? container.decode(Bool.self) {
                self = .bool(boolValue)
            } else if let intValue = try? container.decode(Int.self) {
                self = .int(intValue)
            } else if let doubleValue = try? container.decode(Double.self) {
                self = .double(doubleValue)
            } else {
                self = .string(try container.decode(String.self))
            }
        }

        var rawValue: Any {
            switch self {
            case .string(let value): return value
            case .int(let value): return value
            case .double(let value): return value
            case .bool(let value): return value
            }
        }
    }

    struct Policies: Decodable {
        let execution: ExecutionPolicy?
        let artifacts: ArtifactPolicy?
    }

    struct ExecutionPolicy: Decodable {
        let network: String?
        let cpuSeconds: Int?
        let memoryMB: Int?

        enum CodingKeys: String, CodingKey {
            case network
            case cpuSeconds = "cpu_seconds"
            case memoryMB = "memory_mb"
        }
    }

    struct ArtifactPolicy: Decodable {
        let basePath: String?
        enum CodingKeys: String, CodingKey {
            case basePath = "base_path"
        }
    }

    private let scalarTypes: [String: String] = [
        "Int": "integer",
        "Int32": "integer",
        "Int64": "integer",
        "Double": "number",
        "Float": "number",
        "String": "string",
        "Bool": "boolean"
    ]

    @discardableResult
    func compile(specURL: URL, outputDirectory: URL) throws -> URL {
        let data = try Data(contentsOf: specURL)
        guard let yaml = String(data: data, encoding: .utf8) else {
            throw CompilerError.invalidUTF8
        }

        let decoder = YAMLDecoder()
        let spec = try decoder.decode(ArcSpec.self, from: yaml)

        var schemas: [String: Any] = [:]
        var paths: [String: Any] = [:]

        for op in spec.operators {
            let operationId = sanitizeOperationId(op.id)
            let pathKey = "/" + op.id.replacingOccurrences(of: ".", with: "/")

            let requestSchemaName = "\(operationId)Request"
            let responseSchemaName = "\(operationId)Response"

            schemas[requestSchemaName] = makeRequestSchema(for: op, name: requestSchemaName, schemas: &schemas)
            schemas[responseSchemaName] = makeResponseWrapperSchema(for: op, name: responseSchemaName, schemas: &schemas)

            let pathItem: [String: Any] = [
                "post": [
                    "summary": op.intent,
                    "operationId": operationId,
                    "requestBody": [
                        "required": true,
                        "content": [
                            "application/json": [
                                "schema": ["$ref": "#/components/schemas/\(requestSchemaName)"]
                            ]
                        ]
                    ],
                    "responses": [
                        "200": [
                            "description": "Successful Response",
                            "content": [
                                "application/json": [
                                    "schema": ["$ref": "#/components/schemas/\(responseSchemaName)"]
                                ]
                            ]
                        ],
                        "400": [
                            "$ref": "#/components/responses/BadRequest"
                        ]
                    ]
                ]
            ]

            paths[pathKey] = pathItem
        }

        let components: [String: Any] = [
            "schemas": schemas,
            "responses": [
                "BadRequest": [
                    "description": "Bad request",
                    "content": [
                        "application/json": [
                            "schema": [
                                "type": "object",
                                "properties": [
                                    "error": ["type": "string"]
                                ],
                                "required": ["error"]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        var info: [String: Any] = [
            "title": spec.arc,
            "version": spec.version.value
        ]
        if let corpus = spec.corpus {
            info["x-fountain"] = [
                "corpusId": corpus.id
            ]
        }

        let openAPIDoc: [String: Any] = [
            "openapi": "3.1.0",
            "info": info,
            "paths": paths,
            "components": components
        ]

        let outputDir = outputDirectory
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let slug = slugify(spec.arc)
        let outputURL = outputDir.appendingPathComponent("\(slug).yml")
        let yamlString = try Yams.dump(object: openAPIDoc)
        try yamlString.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    private func makeRequestSchema(for op: Operator, name: String, schemas: inout [String: Any]) -> [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []

        for input in op.input {
            let schema = schemaForType(input.type, schemas: &schemas)
            var propertySchema = schema
            if let defaultValue = input.defaultValue?.rawValue {
                propertySchema["default"] = defaultValue
            }
            properties[input.name] = propertySchema
            if input.required ?? true {
                required.append(input.name)
            }
        }

        var requestSchema: [String: Any] = [
            "type": "object",
            "title": name,
            "properties": properties
        ]
        if !required.isEmpty {
            requestSchema["required"] = required
        }
        return requestSchema
    }

    private func makeResponseWrapperSchema(for op: Operator, name: String, schemas: inout [String: Any]) -> [String: Any] {
        var response: [String: Any] = [
            "type": "object",
            "title": name,
            "properties": [
                "result": schemaForType(op.output.type, schemas: &schemas)
            ],
            "required": ["result"]
        ]
        if let guarantees = op.output.guarantees, !guarantees.isEmpty {
            response["x-fountain-guarantees"] = guarantees
        }
        return response
    }

    private func schemaForType(_ type: String, schemas: inout [String: Any]) -> [String: Any] {
        if let elementType = arrayInfo(type) {
            let itemsSchema = schemaForType(elementType, schemas: &schemas)
            return [
                "type": "array",
                "items": itemsSchema
            ]
        }

        if let primitive = scalarTypes[type] {
            return ["type": primitive]
        }

        // complex type placeholder
        if schemas[type] == nil {
            schemas[type] = [
                "type": "object",
                "title": type,
                "description": "Placeholder schema generated from ArcSpec."
            ]
        }
        return ["$ref": "#/components/schemas/\(type)"]
    }

    private func arrayInfo(_ type: String) -> String? {
        guard type.hasSuffix("[]") else { return nil }
        return String(type.dropLast(2))
    }

    private func sanitizeOperationId(_ id: String) -> String {
        let parts = id.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let camel = parts.map { part -> String in
            guard let first = part.first else { return "" }
            let head = first.isNumber ? "Op" + String(first) : String(first).uppercased()
            let tail = part.dropFirst()
            return head + tail
        }.joined()
        return camel.isEmpty ? "Operation" : camel
    }

    private func slugify(_ text: String) -> String {
        var slug = text.lowercased()
        slug = slug.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "arc" : slug
    }

    enum CompilerError: Error, CustomStringConvertible {
        case invalidUTF8

        var description: String {
            switch self {
            case .invalidUTF8:
                return "ArcSpec file is not valid UTF-8"
            }
        }
    }
}
