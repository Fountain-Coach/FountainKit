import Foundation
import FountainStoreClient

/// Scaffold a new instrument according to Plans/instrument-new-plan.md.
@main
struct InstrumentNew {
    struct Config: Equatable {
        var appId: String
        var agentId: String
        var specName: String
        var visual: Bool
        var metalView: Bool
        var noApp: Bool
    }

    static func main() async {
        do {
            let cfg = try parseConfig()
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            try generate(in: root, config: cfg, dryRun: false)
        } catch {
            fputs("instrument-new error: \(error)\n", stderr)
            exit(1)
        }
    }

    static func parseConfig(arguments: [String] = Array(CommandLine.arguments.dropFirst())) throws -> Config {
        var args = Array(CommandLine.arguments.dropFirst())
        func nextArg(label: String) throws -> String {
            guard !args.isEmpty else {
                throw NSError(domain: "instrument-new", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(label)"])
            }
            return args.removeFirst()
        }

        if args.contains("--help") || args.contains("-h") {
            print("""
            Usage: instrument-new <appId> <agentId> <specName> [--visual|--no-visual] [--metalview] [--no-app]

              appId      Short identifier for the instrument (e.g., llm-chat).
              agentId    Canonical agent id (e.g., fountain.coach/agent/llm-chat/service).
              specName   Spec filename under openapi/v1 (e.g., llm-chat.yml).

            Flags:
              --visual / --no-visual   Whether to scaffold PB-VRT baselines (default: visual).
              --metalview              Also scaffold a MetalViewKit renderer driven by the FGK graph.
              --no-app                 Do not create an executable app target; seed/spec/tests only.
            """)
            exit(0)
        }

        let appId = try nextArg(label: "appId")
        let agentId = try nextArg(label: "agentId")
        let specName = try nextArg(label: "specName")

        var visual = true
        var metalView = false
        var noApp = false

        while !args.isEmpty {
            let flag = args.removeFirst()
            switch flag {
            case "--visual":
                visual = true
            case "--no-visual":
                visual = false
            case "--metalview":
                metalView = true
            case "--no-app":
                noApp = true
            default:
                throw NSError(domain: "instrument-new", code: 2, userInfo: [NSLocalizedDescriptionKey: "unknown flag \(flag)"])
            }
        }

        return Config(appId: appId, agentId: agentId, specName: specName, visual: visual, metalView: metalView, noApp: noApp)
    }

    /// Core entry point (testable): generate or describe scaffolding under `root`.
    static func generate(in root: URL, config cfg: Config, dryRun: Bool) throws {
        if dryRun {
            describePlannedArtifacts(cfg)
            return
        }

        try scaffoldSpec(in: root, cfg: cfg)
        try scaffoldFactsMapping(in: root, cfg: cfg)
        try scaffoldInstrumentIndex(in: root, cfg: cfg)
        describePlannedArtifacts(cfg)
    }

    private static func describePlannedArtifacts(_ cfg: Config) {
        print("[instrument-new] Plan for instrument:")
        print("  appId:    \(cfg.appId)")
        print("  agentId:  \(cfg.agentId)")
        print("  specName: \(cfg.specName)")
        print("  visual:   \(cfg.visual ? "yes" : "no")")
        print("  metalview:\(cfg.metalView ? "yes" : "no")")
        print("  app:      \(cfg.noApp ? "no (seed/spec/tests only)" : "yes (FGK surface app target)")")

        let appId = cfg.appId
        let appIdUpper = appId.prefix(1).uppercased() + appId.dropFirst()

        print("")
        print("Artifacts to create/update (per Plans/instrument-new-plan.md):")
        print("  - Spec: Packages/FountainSpecCuration/openapi/v1/\(cfg.specName)")
        print("  - Facts mapping entry in Tools/openapi-facts-mapping.json for \(cfg.specName) → \(cfg.agentId)")
        print("  - Seeder target: <appId>-seed → Packages/FountainApps/Sources/\(appId)-seed/main.swift")
        print("  - Instrument index entry in Tools/instruments.json for appId=\(appId)")
        print("  - Tests module: Packages/FountainApps/Tests/\(appIdUpper)Tests/")
        if cfg.visual {
            print("    • Baselines directory for PB-VRT snapshots")
        }
        print("    • SurfaceTests + PETests (+ SnapshotTests when visual)")
        if !cfg.noApp {
            print("  - App target: \(appId)-app with FGK surface and optional MetalViewKit renderer")
        }
        if cfg.metalView {
            print("    • MetalViewKit renderer driven by FGKNode/FGKEvent graph")
        }
        print("")
        print("[instrument-new] Scaffolding for spec + mapping + instruments index has been applied.")
        print("                 Seeder, tests, and app surface scaffolding will be added in subsequent revisions.")
    }

    // MARK: - Phase 1: spec + mapping + instruments index

    private static func scaffoldSpec(in root: URL, cfg: Config) throws {
        let specsDir = root
            .appendingPathComponent("Packages/FountainSpecCuration/openapi/v1", isDirectory: true)
        let specURL = specsDir.appendingPathComponent(cfg.specName, isDirectory: false)
        if FileManager.default.fileExists(atPath: specURL.path) {
            return
        }
        try FileManager.default.createDirectory(at: specsDir, withIntermediateDirectories: true)

        let appIdCamel = camelCase(cfg.appId)
        let stub = """
        openapi: 3.1.0
        info:
          title: \(appIdCamel) Instrument API
          version: 1.0.0
        paths: {}
        components: {}
        """
        try stub.trimmingCharacters(in: .whitespacesAndNewlines)
            .appending("\n")
            .data(using: .utf8)?
            .write(to: specURL)
    }

    struct Mapping: Codable, Equatable {
        var spec: String
        var agentId: String
    }

    private static func scaffoldFactsMapping(in root: URL, cfg: Config) throws {
        let mapURL = root.appendingPathComponent("Tools/openapi-facts-mapping.json", isDirectory: false)
        let fm = FileManager.default
        var mappings: [Mapping] = []
        if fm.fileExists(atPath: mapURL.path) {
            let data = try Data(contentsOf: mapURL)
            mappings = try JSONDecoder().decode([Mapping].self, from: data)
        }
        let newMapping = Mapping(spec: cfg.specName, agentId: cfg.agentId)
        if mappings.contains(where: { $0 == newMapping }) {
            return
        }
        mappings.append(newMapping)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(mappings)
        try data.write(to: mapURL)
    }

    struct InstrumentIndexEntry: Codable, Equatable {
        var appId: String
        var agentId: String
        var corpusId: String
        var spec: String
        var runtimeAgentId: String?
        var testModulePath: String?
        var snapshotBaselinesDir: String?
        var requiredTestSymbols: [String]?
    }

    private static func scaffoldInstrumentIndex(in root: URL, cfg: Config) throws {
        let instrumentsURL = root.appendingPathComponent("Tools/instruments.json", isDirectory: false)
        let fm = FileManager.default
        var entries: [InstrumentIndexEntry] = []
        if fm.fileExists(atPath: instrumentsURL.path) {
            let data = try Data(contentsOf: instrumentsURL)
            entries = try JSONDecoder().decode([InstrumentIndexEntry].self, from: data)
        }
        if entries.contains(where: { $0.appId == cfg.appId }) {
            return
        }

        let appIdCamel = camelCase(cfg.appId)
        let testModule = "Packages/FountainApps/Tests/\(appIdCamel)Tests"
        let baselines = cfg.visual ? "\(testModule)/Baselines" : nil
        let requiredSymbols: [String]? = cfg.visual ? [
            "\(appIdCamel)SurfaceTests",
            "\(appIdCamel)PETests",
            "\(appIdCamel)SnapshotTests"
        ] : [
            "\(appIdCamel)SurfaceTests",
            "\(appIdCamel)PETests"
        ]

        let entry = InstrumentIndexEntry(
            appId: cfg.appId,
            agentId: cfg.agentId,
            corpusId: cfg.appId,
            spec: cfg.specName,
            runtimeAgentId: nil,
            testModulePath: testModule,
            snapshotBaselinesDir: baselines,
            requiredTestSymbols: requiredSymbols
        )
        entries.append(entry)

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(entries)
        try data.write(to: instrumentsURL)
    }

    private static func camelCase(_ id: String) -> String {
        let parts = id.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let joined = parts.map { part -> String in
            guard let first = part.first else { return "" }
            return String(first).uppercased() + part.dropFirst().lowercased()
        }.joined()
        return joined.isEmpty ? id : joined
    }
}
