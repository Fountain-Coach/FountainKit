import Foundation
import MIDI2

public struct FlexEnvelope: Codable, Equatable, Sendable {
    public let v: Int
    public let ts: UInt64
    public let corr: String
    public let intent: String
    public let body: JSONValue

    public init(v: Int, ts: UInt64, corr: String, intent: String, body: JSONValue) {
        self.v = v
        self.ts = ts
        self.corr = corr
        self.intent = intent
        self.body = body
    }
}

public enum MIDI2Core {
    enum CoreError: Error { case encodingFailed, decodingFailed }

    public static func encode(_ env: FlexEnvelope) throws -> Ump128 {
        let data = try JSONEncoder().encode(env)
        guard let text = String(data: data, encoding: .utf8) else { throw CoreError.encodingFailed }
        let msg = FlexText(address: .group(Uint4(0)!), text: text)
        return msg.encode()
    }

    public static func decode(_ packet: Ump128) throws -> FlexEnvelope {
        guard let msg = FlexText.decode(packet) else { throw CoreError.decodingFailed }
        let data = Data(msg.text.utf8)
        return try JSONDecoder().decode(FlexEnvelope.self, from: data)
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
