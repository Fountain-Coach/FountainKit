// Generated Swift models - regenerated from midi/models/*.json
// DO NOT EDIT MANUALLY

public struct MessageType: Codable, Equatable, Sendable {
    public let name: String
    public let status: UInt8
    public let description: String
}

public struct EnumDefinition: Codable, Equatable, Sendable {
    public let name: String
    public let cases: [String]
}

public struct Bitfield: Codable, Equatable, Sendable {
    public struct Bit: Codable, Equatable, Sendable {
        public let name: String
        public let offset: Int
        public let width: Int
    }
    public let name: String
    public let bits: [Bit]
}

public struct RangeDefinition: Codable, Equatable, Sendable {
    public let name: String
    public let min: Int
    public let max: Int
}
public let messageTypes: [MessageType] = [
    MessageType(name: "noteOn", status: 144, description: "Note On message"),
]

public let enumDefinitions: [EnumDefinition] = [
    EnumDefinition(name: "Direction", cases: ["up", "down"]),
]

public let bitfields: [Bitfield] = [
    Bitfield(name: "NoteFlags", bits: [
        .init(name: "isSharp", offset: 0, width: 1),
        .init(name: "isFlat", offset: 1, width: 1),
    ]),
]

public let rangeDefinitions: [RangeDefinition] = [
    RangeDefinition(name: "VelocityRange", min: 0, max: 127),
]

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
