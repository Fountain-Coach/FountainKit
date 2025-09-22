// Models for Tool Server

public struct BitField: Codable {
    public let bits: [Int]
    public let name: String
}

public struct EnumCase: Codable {
    public let name: String
    public let value: Int
}

public struct EnumSpec: Codable {
    public let cases: [EnumCase]
    public let field: String
}

public struct ExportMatrixRequest: Codable {
    public let bitfields: Bool
    public let enums: Bool
    public let index: Index
    public let ranges: Bool
}

public struct Index: Codable {
    public let documents: [[String: String]]
}

public struct Matrix: Codable {
    public let bitfields: [BitField]
    public let enums: [EnumSpec]
    public let messages: [MatrixEntry]
    public let ranges: [RangeSpec]
    public let schemaVersion: String
    public let terms: [MatrixEntry]
}

public struct MatrixEntry: Codable {
    public let page: Int
    public let text: String
    public let x: Int
    public let y: Int
}

public struct QueryRequest: Codable {
    public let index: Index
    public let pageRange: String
    public let q: String
}

public struct QueryResponse: Codable {
    public let hits: [[String: String]]
}

public struct RangeSpec: Codable {
    public let field: String
    public let max: Int
    public let min: Int
}

public struct ScanRequest: Codable {
    public let includeText: Bool
    public let inputs: [String]
    public let sha256: Bool
}

public struct ToolRequest: Codable {
    public let args: [String]
    public let request_id: String
}

public struct ValidationResult: Codable {
    public let issues: [String]
    public let ok: Bool
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
