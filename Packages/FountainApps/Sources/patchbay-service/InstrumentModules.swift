import Foundation

// Service-side instrument providers (schema + identity) to keep seeds/CRUD consistent.

enum InstrumentProviders {
    static func provider(for kind: Components.Schemas.InstrumentKind) -> any InstrumentProvider {
        switch kind.rawValue {
        case "mvk.triangle": return MVKTriangle()
        case "mvk.quad": return MVKQuad()
        case "audiotalk.chat": return AudioTalkChat()
        default: return DefaultProvider()
        }
    }

    static func makeInstrument(id: String,
                               kind: Components.Schemas.InstrumentKind,
                               title: String? = nil,
                               x: Int, y: Int, w: Int, h: Int) -> Components.Schemas.Instrument {
        let p = provider(for: kind)
        let ident = p.makeIdentity(id: id, title: title)
        let schema = p.makeSchema()
        return .init(id: id, kind: kind, title: title, x: x, y: y, w: w, h: h, identity: ident, propertySchema: schema, propertyDefaults: p.makeDefaults())
    }
}

protocol InstrumentProvider {
    func makeIdentity(id: String, title: String?) -> Components.Schemas.InstrumentIdentity
    func makeSchema() -> Components.Schemas.PropertySchema
    func makeDefaults() -> Components.Schemas.Instrument.propertyDefaultsPayload?
}

struct DefaultProvider: InstrumentProvider {
    func makeIdentity(id: String, title: String?) -> Components.Schemas.InstrumentIdentity {
        .init(manufacturer: "Fountain", product: "Instrument", displayName: title ?? id, instanceId: id, muid28: 0, hasUMPInput: true, hasUMPOutput: true)
    }
    func makeSchema() -> Components.Schemas.PropertySchema { .init(version: 1, properties: []) }
    func makeDefaults() -> Components.Schemas.Instrument.propertyDefaultsPayload? { nil }
}

struct MVKTriangle: InstrumentProvider {
    func makeIdentity(id: String, title: String?) -> Components.Schemas.InstrumentIdentity {
        .init(manufacturer: "Fountain", product: "MetalTriangle", displayName: "MetalTriangleView#\(id)", instanceId: id, muid28: 0x00123456, hasUMPInput: true, hasUMPOutput: true)
    }
    func makeSchema() -> Components.Schemas.PropertySchema {
        .init(version: 1, properties: [
            .init(name: "zoom", _type: .float, min: 0.1, max: 4.0, step: 0.05, _default: .case1(1.0), enumValues: nil, aliases: nil),
            .init(name: "tint.r", _type: .float, min: 0.0, max: 1.0, step: 0.01, _default: .case1(1.0), enumValues: nil, aliases: ["tint"]),
            .init(name: "tint.g", _type: .float, min: 0.0, max: 1.0, step: 0.01, _default: .case1(1.0), enumValues: nil, aliases: nil),
            .init(name: "tint.b", _type: .float, min: 0.0, max: 1.0, step: 0.01, _default: .case1(1.0), enumValues: nil, aliases: nil)
        ])
    }
    func makeDefaults() -> Components.Schemas.Instrument.propertyDefaultsPayload? {
        .init(additionalProperties: ["zoom": .case1(1.0)])
    }
}

struct MVKQuad: InstrumentProvider {
    func makeIdentity(id: String, title: String?) -> Components.Schemas.InstrumentIdentity {
        .init(manufacturer: "Fountain", product: "MetalQuad", displayName: "MetalTexturedQuadView#\(id)", instanceId: id, muid28: 0x00123457, hasUMPInput: true, hasUMPOutput: true)
    }
    func makeSchema() -> Components.Schemas.PropertySchema {
        .init(version: 1, properties: [
            .init(name: "rotationSpeed", _type: .float, min: 0.0, max: 4.0, step: 0.01, _default: .case1(0.35), enumValues: nil, aliases: nil),
            .init(name: "zoom", _type: .float, min: 0.1, max: 4.0, step: 0.05, _default: .case1(1.0), enumValues: nil, aliases: nil),
            .init(name: "tint.r", _type: .float, min: 0.0, max: 1.0, step: 0.01, _default: .case1(1.0), enumValues: nil, aliases: ["tint"]),
            .init(name: "tint.g", _type: .float, min: 0.0, max: 1.0, step: 0.01, _default: .case1(1.0), enumValues: nil, aliases: nil),
            .init(name: "tint.b", _type: .float, min: 0.0, max: 1.0, step: 0.01, _default: .case1(1.0), enumValues: nil, aliases: nil)
        ])
    }
    func makeDefaults() -> Components.Schemas.Instrument.propertyDefaultsPayload? {
        .init(additionalProperties: ["rotationSpeed": .case1(0.35)])
    }
}

struct AudioTalkChat: InstrumentProvider {
    func makeIdentity(id: String, title: String?) -> Components.Schemas.InstrumentIdentity {
        .init(manufacturer: "Fountain", product: "AudioTalkChat", displayName: "AudioTalkChat#\(id)", instanceId: id, muid28: 0x00123458, hasUMPInput: true, hasUMPOutput: true)
    }
    func makeSchema() -> Components.Schemas.PropertySchema {
        .init(version: 1, properties: [
            .init(name: "draft", _type: .string, min: nil, max: nil, step: nil, _default: .case4(""), enumValues: nil, aliases: nil),
            .init(name: "provider", _type: .string, min: nil, max: nil, step: nil, _default: .case4("gateway"), enumValues: ["gateway","openai","local"], aliases: nil),
            .init(name: "model", _type: .string, min: nil, max: nil, step: nil, _default: .case4("o4-mini"), enumValues: nil, aliases: nil),
            .init(name: "stream", _type: .bool, min: nil, max: nil, step: nil, _default: .case3(true), enumValues: nil, aliases: nil)
        ])
    }
    func makeDefaults() -> Components.Schemas.Instrument.propertyDefaultsPayload? {
        .init(additionalProperties: [
            "provider": .case4("gateway"),
            "model": .case4("o4-mini"),
            "stream": .case3(true)
        ])
    }
}
