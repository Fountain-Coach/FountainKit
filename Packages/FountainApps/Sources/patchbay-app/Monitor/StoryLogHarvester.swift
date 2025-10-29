import Foundation
import AppKit

@MainActor
final class StoryLogHarvester {
    struct SessionSummary: Codable {
        var file: String
        var eventCount: Int
        var topics: [String:Int]
        var ids: [String]
        var startTs: String?
        var endTs: String?
    }
    struct Knowledge: Codable {
        var version: Int = 1
        var generatedAt: String
        var sessions: [SessionSummary]
        var totals: [String:Int]
        var uniqueIds: [String]
    }

    static func harvestAll() throws -> URL {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let logsDir = cwd.appendingPathComponent(".fountain/corpus/ump", isDirectory: true)
        let outDir = cwd.appendingPathComponent(".fountain/corpus/knowledge", isDirectory: true)
        try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        guard let files = try? fm.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: nil) else {
            throw NSError(domain: "StoryLogHarvester", code: 1, userInfo: [NSLocalizedDescriptionKey: "No UMP logs directory at \(logsDir.path)"])
        }
        var sessions: [SessionSummary] = []
        var totals: [String:Int] = [:]
        var allIds: Set<String> = []
        for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where f.lastPathComponent.hasSuffix(".ndjson") {
            guard let data = try? Data(contentsOf: f), let text = String(data: data, encoding: .utf8) else { continue }
            var topics: [String:Int] = [:]
            var ids: Set<String> = []
            var count = 0
            var startTs: String? = nil
            var endTs: String? = nil
            text.enumerateLines { line, _ in
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return }
                count += 1
                if let t = obj["ts"] as? String { if startTs == nil { startTs = t }; endTs = t }
                if let topic = obj["topic"] as? String { topics[topic, default: 0] += 1; totals[topic, default: 0] += 1 }
                if let data = obj["data"] as? [String: Any] {
                    if let id = data["id"] as? String { ids.insert(id) }
                    if let arr = data["ids"] as? [Any] { for v in arr { if let s = v as? String { ids.insert(s) } } }
                    if let sel = data["selected"] as? [Any] { for v in sel { if let s = v as? String { ids.insert(s) } } }
                    if let before = data["before"] as? [Any] { for v in before { if let s = v as? String { ids.insert(s) } } }
                    if let after = data["after"] as? [Any] { for v in after { if let s = v as? String { ids.insert(s) } } }
                }
            }
            allIds.formUnion(ids)
            sessions.append(SessionSummary(file: f.lastPathComponent, eventCount: count, topics: topics, ids: Array(ids).sorted(), startTs: startTs, endTs: endTs))
        }
        let now = ISO8601DateFormatter().string(from: Date())
        let knowledge = Knowledge(generatedAt: now, sessions: sessions, totals: totals, uniqueIds: Array(allIds).sorted())
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(knowledge)
        let out = outDir.appendingPathComponent("knowledge-\(timestamp()).json")
        try data.write(to: out)
        return out
    }

    static func openKnowledgeFolder() {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let outDir = cwd.appendingPathComponent(".fountain/corpus/knowledge", isDirectory: true)
        NSWorkspace.shared.open(outDir)
    }

    private static func timestamp() -> String {
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd-HHmmss"
        return df.string(from: Date())
    }
}

