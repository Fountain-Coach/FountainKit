import Foundation
import FountainStoreClient

public struct MemChatExport: Codable {
    public var corpusId: String
    public var chatTurns: [[String: AnyCodable]]
    public var attachments: [[String: AnyCodable]]
    public var patterns: [[String: AnyCodable]]
}

public struct AnyCodable: Codable {
    public let value: Any
    public init(_ value: Any) { self.value = value }
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { value = s; return }
        if let i = try? container.decode(Int.self) { value = i; return }
        if let d = try? container.decode(Double.self) { value = d; return }
        if let b = try? container.decode(Bool.self) { value = b; return }
        if let arr = try? container.decode([AnyCodable].self) { value = arr.map { $0.value }; return }
        if let dict = try? container.decode([String: AnyCodable].self) { value = dict.mapValues { $0.value }; return }
        value = NSNull()
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let s as String: try container.encode(s)
        case let i as Int: try container.encode(i)
        case let d as Double: try container.encode(d)
        case let b as Bool: try container.encode(b)
        case let arr as [Any]: try container.encode(arr.map { AnyCodable($0) })
        case let dict as [String: Any]: try container.encode(dict.mapValues { AnyCodable($0) })
        default: try container.encodeNil()
        }
    }
}

public enum MemChatExportError: Error { case invalidJSON }

public actor MemChatExporter {
    let store: FountainStoreClient
    public init(store: FountainStoreClient) { self.store = store }

    public func export(corpusId: String) async throws -> Data {
        func toAnyCodable(_ obj: [String: Any]) -> [String: AnyCodable] {
            obj.mapValues { AnyCodable($0) }
        }
        func fetch(collection: String) async throws -> [Data] {
            let resp = try await store.query(corpusId: corpusId, collection: collection, query: Query(filters: ["corpusId": corpusId], limit: 5000, offset: 0))
            return resp.documents
        }
        let turnsD = try await fetch(collection: "chat-turns")
        let attachmentsD = try await fetch(collection: "attachments")
        let patternsD = try await fetch(collection: "patterns")
        let turns = turnsD.compactMap { (try? JSONSerialization.jsonObject(with: $0) as? [String: Any]).map(toAnyCodable) }
        let attachments = attachmentsD.compactMap { (try? JSONSerialization.jsonObject(with: $0) as? [String: Any]).map(toAnyCodable) }
        let patterns = patternsD.compactMap { (try? JSONSerialization.jsonObject(with: $0) as? [String: Any]).map(toAnyCodable) }
        let payload = MemChatExport(
            corpusId: corpusId,
            chatTurns: turns,
            attachments: attachments,
            patterns: patterns
        )
        return try JSONEncoder().encode(payload)
    }

    public func `import`(into targetCorpusId: String, data: Data) async throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MemChatExportError.invalidJSON
        }
        func array(_ key: String) -> [[String: Any]] {
            (root[key] as? [[String: Any]]) ?? []
        }
        for var json in array("chatTurns") {
            json["corpusId"] = targetCorpusId
            guard let id = (json["recordId"] as? String) else { continue }
            let body = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            try await store.putDoc(corpusId: targetCorpusId, collection: "chat-turns", id: id, body: body)
        }
        for var json in array("attachments") {
            json["corpusId"] = targetCorpusId
            let id = (json["attachmentId"] as? String) ?? (json["id"] as? String) ?? UUID().uuidString
            let body = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            try await store.putDoc(corpusId: targetCorpusId, collection: "attachments", id: id, body: body)
        }
        for var json in array("patterns") {
            json["corpusId"] = targetCorpusId
            let id = (json["patternsId"] as? String) ?? UUID().uuidString
            let body = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            try await store.putDoc(corpusId: targetCorpusId, collection: "patterns", id: id, body: body)
        }
    }
}
