import Foundation
import MIDI2Core
import MIDI2

public enum FlexCtlError: Error {
    case usage
    case parseFailed
}

public func loadUMP(path: String) throws -> [UInt32] {
    let url = URL(fileURLWithPath: path)
    let text = try String(contentsOf: url, encoding: .utf8)
    let lines = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("©") }
    let joined = lines.joined()
    let trimmed = joined.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
    let parts = trimmed.split(separator: ",")
    let words = parts.compactMap { UInt32($0.trimmingCharacters(in: .whitespaces)) }
    guard words.count == parts.count else { throw FlexCtlError.parseFailed }
    return words
}

public func sendEnvelope(path: String, corrOverride: String?) throws -> [UInt32] {
    let url = URL(fileURLWithPath: path)
    var env = try JSONDecoder().decode(FlexEnvelope.self, from: Data(contentsOf: url))
    if let corr = corrOverride {
        env = FlexEnvelope(v: env.v, ts: env.ts, corr: corr, intent: env.intent, body: env.body)
    }
    let packet = try MIDI2Core.encode(env)
    return packet.words
}

public func replayUMP(path: String) throws -> FlexEnvelope {
    let words = try loadUMP(path: path)
    guard let packet = Ump128(words: words) else { throw FlexCtlError.parseFailed }
    return try MIDI2Core.decode(packet)
}

public func tail(corr: String, journalDir: String) throws -> String {
    let dir = URL(fileURLWithPath: journalDir)
    let file = dir.appendingPathComponent("\(corr)-res.json")
    let data = try Data(contentsOf: file)
    return String(decoding: data, as: UTF8.self)
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
