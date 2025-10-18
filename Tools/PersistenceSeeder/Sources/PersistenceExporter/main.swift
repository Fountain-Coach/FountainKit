import Foundation
import PersistenceSeederKit

@main
struct PersistenceExporterCLI {
    static func main() async throws {
        var persistURLString: String?
        var persistAPIKey: String?
        var corpusId: String?
        var outputDir: String = "./Packages/FountainSpecCuration/fixtures/persist"
        var pageLimit = 200
        var segLimit = 200
        var includeAll = false
        var includeKinds: Set<String> = ["pages", "segments"]

        var idx = 1
        let args = CommandLine.arguments
        while idx < args.count {
            let arg = args[idx]
            switch arg {
            case "--persist-url":
                guard idx + 1 < args.count else { return usage("--persist-url requires a value") }
                persistURLString = args[idx + 1]
                idx += 2
            case "--persist-api-key":
                guard idx + 1 < args.count else { return usage("--persist-api-key requires a value") }
                persistAPIKey = args[idx + 1]
                idx += 2
            case "--corpus":
                guard idx + 1 < args.count else { return usage("--corpus requires a value") }
                corpusId = args[idx + 1]
                idx += 2
            case "--out":
                guard idx + 1 < args.count else { return usage("--out requires a value") }
                outputDir = args[idx + 1]
                idx += 2
            case "--page-limit":
                guard idx + 1 < args.count, let v = Int(args[idx + 1]), v > 0 else { return usage("--page-limit requires a positive integer") }
                pageLimit = v
                idx += 2
            case "--segment-limit":
                guard idx + 1 < args.count, let v = Int(args[idx + 1]), v > 0 else { return usage("--segment-limit requires a positive integer") }
                segLimit = v
                idx += 2
            case "--include":
                guard idx + 1 < args.count else { return usage("--include requires a comma-separated list") }
                includeKinds = Set(args[idx + 1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
                idx += 2
            case "--all":
                includeAll = true
                idx += 1
            case "--help", "-h":
                printUsage(); return
            default:
                return usage("Unexpected argument: \(arg)")
            }
        }

        guard let persistURLString, let baseURL = URL(string: persistURLString), let corpusId else {
            return usage("--persist-url and --corpus are required")
        }

        let client = PersistServiceClient(baseURL: baseURL, apiKey: persistAPIKey)

        if includeAll { includeKinds = ["pages", "segments", "entities", "tables", "analyses"] }

        var allPages: [PersistServiceClient.Page] = []
        var allSegments: [PersistServiceClient.Segment] = []
        var allEntities: [PersistServiceClient.Entity] = []
        var allTables: [PersistServiceClient.Table] = []
        var allAnalyses: [PersistServiceClient.Analysis] = []

        if includeKinds.contains("pages") {
            var offset = 0
            while true {
                let batch = try await client.listPages(corpusId: corpusId, limit: pageLimit, offset: offset)
                allPages.append(contentsOf: batch.pages)
                if allPages.count >= batch.total || batch.pages.isEmpty { break }
                offset += pageLimit
            }
            allPages.sort { $0.pageId < $1.pageId }
        }
        if includeKinds.contains("segments") {
            var soff = 0
            while true {
                let batch = try await client.listSegments(corpusId: corpusId, limit: segLimit, offset: soff)
                allSegments.append(contentsOf: batch.segments)
                if allSegments.count >= batch.total || batch.segments.isEmpty { break }
                soff += segLimit
            }
            allSegments.sort { ($0.pageId, $0.segmentId) < ($1.pageId, $1.segmentId) }
        }
        if includeKinds.contains("entities") {
            var eoff = 0
            while true {
                let batch = try await client.listEntities(corpusId: corpusId, limit: segLimit, offset: eoff)
                allEntities.append(contentsOf: batch.entities)
                if allEntities.count >= batch.total || batch.entities.isEmpty { break }
                eoff += segLimit
            }
            allEntities.sort { ($0.type, $0.name, $0.entityId) < ($1.type, $1.name, $1.entityId) }
        }
        if includeKinds.contains("tables") {
            var toff = 0
            while true {
                let batch = try await client.listTables(corpusId: corpusId, limit: segLimit, offset: toff)
                allTables.append(contentsOf: batch.tables)
                if allTables.count >= batch.total || batch.tables.isEmpty { break }
                toff += segLimit
            }
            allTables.sort { ($0.pageId, $0.tableId) < ($1.pageId, $1.tableId) }
        }
        if includeKinds.contains("analyses") {
            var aoff = 0
            while true {
                let batch = try await client.listAnalyses(corpusId: corpusId, limit: segLimit, offset: aoff)
                allAnalyses.append(contentsOf: batch.analyses)
                if allAnalyses.count >= batch.total || batch.analyses.isEmpty { break }
                aoff += segLimit
            }
            allAnalyses.sort { ($0.pageId, $0.analysisId) < ($1.pageId, $1.analysisId) }
        }

        // Write files under <outputDir>/<corpusId>/{pages.json,segments.json}
        let fm = FileManager.default
        let baseOut = URL(fileURLWithPath: outputDir, isDirectory: true).appendingPathComponent(corpusId, isDirectory: true)
        try fm.createDirectory(at: baseOut, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if includeKinds.contains("pages") {
            struct PageOut: Codable { let corpusId: String; let pageId: String; let url: String; let host: String; let title: String }
            let pagePayload = allPages.map { PageOut(corpusId: $0.corpusId, pageId: $0.pageId, url: $0.url, host: $0.host, title: $0.title) }
            try encoder.encode(pagePayload).write(to: baseOut.appendingPathComponent("pages.json"))
        }
        if includeKinds.contains("segments") {
            struct SegmentOut: Codable { let corpusId: String; let segmentId: String; let pageId: String; let kind: String; let text: String }
            let segPayload = allSegments.map { SegmentOut(corpusId: $0.corpusId, segmentId: $0.segmentId, pageId: $0.pageId, kind: $0.kind, text: $0.text) }
            try encoder.encode(segPayload).write(to: baseOut.appendingPathComponent("segments.json"))
        }
        if includeKinds.contains("entities") {
            struct EntityOut: Codable { let corpusId: String; let entityId: String; let name: String; let type: String }
            let entPayload = allEntities.map { EntityOut(corpusId: $0.corpusId, entityId: $0.entityId, name: $0.name, type: $0.type) }
            try encoder.encode(entPayload).write(to: baseOut.appendingPathComponent("entities.json"))
        }
        if includeKinds.contains("tables") {
            struct TableOut: Codable { let corpusId: String; let tableId: String; let pageId: String; let csv: String }
            let tabPayload = allTables.map { TableOut(corpusId: $0.corpusId, tableId: $0.tableId, pageId: $0.pageId, csv: $0.csv) }
            try encoder.encode(tabPayload).write(to: baseOut.appendingPathComponent("tables.json"))
        }
        if includeKinds.contains("analyses") {
            struct AnalysisOut: Codable { let corpusId: String; let analysisId: String; let pageId: String; let summary: String }
            let anaPayload = allAnalyses.map { AnalysisOut(corpusId: $0.corpusId, analysisId: $0.analysisId, pageId: $0.pageId, summary: $0.summary) }
            try encoder.encode(anaPayload).write(to: baseOut.appendingPathComponent("analyses.json"))
        }

        fputs("Exported → \(baseOut.path) [pages: \(allPages.count), segments: \(allSegments.count), entities: \(allEntities.count), tables: \(allTables.count), analyses: \(allAnalyses.count)]\n", stderr)
    }

    private static func usage(_ message: String) {
        fputs("ERROR: \(message)\n", stderr)
        printUsage()
    }

    private static func printUsage() {
        print("""
        persistence-exporter

        Usage:
          persistence-exporter --persist-url <url> --corpus <id> [--out <dir>] [--persist-api-key <key>]

        Options:
          --persist-url <url>      Base URL of Persist service (e.g. http://127.0.0.1:8005)
          --corpus <id>            Corpus identifier to export
          --out <dir>              Output directory (default: Packages/FountainSpecCuration/fixtures/persist)
          --persist-api-key <key>  Optional API key for Persist
          --page-limit <n>         Page fetch batch size (default: 200)
          --segment-limit <n>      Segment fetch batch size (default: 200)
          --include a,b,c          Which kinds to include (pages,segments,entities,tables,analyses)
          --all                    Include all kinds
        """)
    }
}
