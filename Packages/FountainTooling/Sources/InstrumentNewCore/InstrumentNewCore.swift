import Foundation
import FountainStoreClient

/// Core implementation for the `instrument-new` tool.
public struct InstrumentNew {
    public struct Config: Equatable {
        public var appId: String
        public var agentId: String
        public var specName: String
        public var visual: Bool
        public var metalView: Bool
        public var noApp: Bool

        public init(appId: String, agentId: String, specName: String, visual: Bool, metalView: Bool, noApp: Bool) {
            self.appId = appId
            self.agentId = agentId
            self.specName = specName
            self.visual = visual
            self.metalView = metalView
            self.noApp = noApp
        }
    }

    public static func parseConfig(arguments: [String] = Array(CommandLine.arguments.dropFirst())) throws -> Config {
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
              --visual / --no-visual   Whether to scaffold FCIS-VRT Render baselines (default: visual).
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
    public static func generate(in root: URL, config cfg: Config, dryRun: Bool) throws {
        if dryRun {
            describePlannedArtifacts(cfg)
            return
        }

        try scaffoldSpec(in: root, cfg: cfg)
        try scaffoldFactsMapping(in: root, cfg: cfg)
        try scaffoldInstrumentIndex(in: root, cfg: cfg)
        try scaffoldSeeder(in: root, cfg: cfg)
        try scaffoldTests(in: root, cfg: cfg)
        if cfg.visual && !cfg.noApp {
            try scaffoldApp(in: root, cfg: cfg)
        }
        try runValidationIfAvailable(in: root, cfg: cfg)
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
            print("    • Baselines directory for FCIS-VRT Render snapshots")
        }
        print("    • SurfaceTests + PETests (+ SnapshotTests when visual)")
        if !cfg.noApp {
            print("  - App target: \(appId)-app with FGK surface and optional MetalViewKit renderer")
        }
        if cfg.metalView {
            print("    • MetalViewKit renderer driven by FGKNode/FGKEvent graph")
        }
        print("")
        print("[instrument-new] Scaffolding for spec + mapping + instruments index + seed target + test module has been applied.")
        if cfg.visual && !cfg.noApp {
            print("                 App surface target has also been scaffolded.")
        } else {
            print("                 App surface scaffolding is disabled for this configuration.")
        }
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
        paths:
          /prompt/state:
            get:
              operationId: get\(appIdCamel)State
              summary: Get canonical state for the \(appIdCamel) instrument.
              x-fountain.allow-as-tool: true
              responses:
                '200':
                  description: Current instrument state.
                  content:
                    application/json:
                      schema:
                        $ref: '#/components/schemas/InstrumentState'
          /prompt/set:
            post:
              operationId: set\(appIdCamel)State
              summary: Apply a state update or command for the \(appIdCamel) instrument.
              x-fountain.allow-as-tool: true
              requestBody:
                required: true
                content:
                  application/json:
                    schema:
                      $ref: '#/components/schemas/InstrumentCommand'
              responses:
                '200':
                  description: Updated instrument state.
                  content:
                    application/json:
                      schema:
                        $ref: '#/components/schemas/InstrumentState'
        components:
          schemas:
            InstrumentState:
              type: object
              description: >
                TODO: Describe the canonical state payload for the \(cfg.appId) instrument.
              additionalProperties: true
            InstrumentCommand:
              type: object
              description: >
                TODO: Describe commands or updates accepted by the \(cfg.appId) instrument.
              additionalProperties: true
        """
        try stub.trimmingCharacters(in: .whitespacesAndNewlines)
            .appending("\n")
            .data(using: .utf8)?
            .write(to: specURL)
    }

    public struct Mapping: Codable, Equatable {
        public var spec: String
        public var agentId: String

        public init(spec: String, agentId: String) {
            self.spec = spec
            self.agentId = agentId
        }
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

    public struct InstrumentIndexEntry: Codable, Equatable {
        public var appId: String
        public var agentId: String
        public var corpusId: String
        public var spec: String
        public var runtimeAgentId: String?
        public var testModulePath: String?
        public var snapshotBaselinesDir: String?
        public var requiredTestSymbols: [String]?

        public init(
            appId: String,
            agentId: String,
            corpusId: String,
            spec: String,
            runtimeAgentId: String?,
            testModulePath: String?,
            snapshotBaselinesDir: String?,
            requiredTestSymbols: [String]?
        ) {
            self.appId = appId
            self.agentId = agentId
            self.corpusId = corpusId
            self.spec = spec
            self.runtimeAgentId = runtimeAgentId
            self.testModulePath = testModulePath
            self.snapshotBaselinesDir = snapshotBaselinesDir
            self.requiredTestSymbols = requiredTestSymbols
        }
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

    // MARK: - Phase 2: Teatro prompt + facts seeder

    private static func scaffoldSeeder(in root: URL, cfg: Config) throws {
        try scaffoldSeedSources(in: root, cfg: cfg)
        try scaffoldSeedTarget(in: root, cfg: cfg)
    }

    private static func scaffoldSeedSources(in root: URL, cfg: Config) throws {
        let seedsDir = root
            .appendingPathComponent("Packages/FountainApps/Sources", isDirectory: true)
            .appendingPathComponent("\(cfg.appId)-seed", isDirectory: true)
        let mainSwift = seedsDir.appendingPathComponent("main.swift", isDirectory: false)
        let fm = FileManager.default
        if fm.fileExists(atPath: mainSwift.path) {
            return
        }
        try fm.createDirectory(at: seedsDir, withIntermediateDirectories: true)

        let appId = cfg.appId
        let appIdCamel = camelCase(appId)
        let seedTypeName = "\(appIdCamel)Seed"

        var lines: [String] = []
        lines.append("import Foundation")
        lines.append("import FountainStoreClient")
        lines.append("import LauncherSignature")
        lines.append("")
        lines.append("@main")
        lines.append("struct \(seedTypeName) {")
        lines.append("    static func main() async {")
        lines.append("        let env = ProcessInfo.processInfo.environment")
        lines.append("        if env[\"FOUNTAIN_SKIP_LAUNCHER_SIG\"] != \"1\" { verifyLauncherSignature() }")
        lines.append("")
        lines.append("        let corpusId = env[\"CORPUS_ID\"] ?? \"\(appId)\"")
        lines.append("        let store = resolveStore()")
        lines.append("        do {")
        lines.append("            _ = try await store.createCorpus(corpusId, metadata: [\"app\": \"\(appId)\", \"kind\": \"teatro+instrument\"])")
        lines.append("        } catch {")
        lines.append("            // corpus may already exist; ignore")
        lines.append("        }")
        lines.append("")
        lines.append("        let pageId = \"prompt:\(appId)\"")
        lines.append("        let page = Page(")
        lines.append("            corpusId: corpusId,")
        lines.append("            pageId: pageId,")
        lines.append("            url: \"store://prompt/\(appId)\",")
        lines.append("            host: \"store\",")
        lines.append("            title: \"\(appIdCamel) Instrument — Teatro Prompt\"")
        lines.append("        )")
        lines.append("        _ = try? await store.addPage(page)")
        lines.append("")
        lines.append("        let prompt = teatroPrompt()")
        lines.append("        _ = try? await store.addSegment(.init(")
        lines.append("            corpusId: corpusId,")
        lines.append("            segmentId: \"\\(pageId):teatro\",")
        lines.append("            pageId: pageId,")
        lines.append("            kind: \"teatro.prompt\",")
        lines.append("            text: prompt")
        lines.append("        ))")
        lines.append("")
        lines.append("        let facts: [String: Any] = [")
        lines.append("            \"instruments\": [[")
        lines.append("                \"id\": \"\(appId)\",")
        lines.append("                \"manufacturer\": \"Fountain\",")
        lines.append("                \"product\": \"\(appIdCamel)\",")
        lines.append("                \"instanceId\": \"\(appId)-1\",")
        lines.append("                \"displayName\": \"\(appIdCamel)\",")
        lines.append("                \"pe\": [")
        lines.append("                    \"canvas.zoom\",")
        lines.append("                    \"canvas.translation.x\",")
        lines.append("                    \"canvas.translation.y\"")
        lines.append("                ]")
        lines.append("            ]],")
        lines.append("            \"invariants\": [")
        lines.append("                \"TODO: refine instrument invariants for \(appId)\"")
        lines.append("            ]")
        lines.append("        ]")
        lines.append("        if")
        lines.append("            let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted]),")
        lines.append("            let json = String(data: data, encoding: .utf8)")
        lines.append("        {")
        lines.append("            _ = try? await store.addSegment(.init(")
        lines.append("                corpusId: corpusId,")
        lines.append("                segmentId: \"\\(pageId):facts\",")
        lines.append("                pageId: pageId,")
        lines.append("                kind: \"facts\",")
        lines.append("                text: json")
        lines.append("            ))")
        lines.append("        }")
        lines.append("")
        lines.append("        print(prompt)")
        lines.append("        print(\"\\nseeded \(appId) prompt → corpusId=\\(corpusId) pageId=\\(pageId)\")")
        lines.append("    }")
        lines.append("")
        lines.append("    static func resolveStore() -> FountainStoreClient {")
        lines.append("        let env = ProcessInfo.processInfo.environment")
        lines.append("        if let dir = env[\"FOUNTAINSTORE_DIR\"], !dir.isEmpty {")
        lines.append("            let url: URL")
        lines.append("            if dir.hasPrefix(\"~\") {")
        lines.append("                url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true)")
        lines.append("            } else {")
        lines.append("                url = URL(fileURLWithPath: dir, isDirectory: true)")
        lines.append("            }")
        lines.append("            if let disk = try? DiskFountainStoreClient(rootDirectory: url) {")
        lines.append("                return FountainStoreClient(client: disk)")
        lines.append("            }")
        lines.append("        }")
        lines.append("        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)")
        lines.append("        if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(\".fountain/store\", isDirectory: true)) {")
        lines.append("            return FountainStoreClient(client: disk)")
        lines.append("        }")
        lines.append("        return FountainStoreClient(client: EmbeddedFountainStoreClient())")
        lines.append("    }")
        lines.append("")
        lines.append("    static func teatroPrompt() -> String {")
        lines.append("        return \"Scene: \(appIdCamel) Instrument — baseline stub.\\\\n\" +")
        lines.append("            \"- Describe scene, layout, PE properties, and robot invariants for \(appId).\"")
        lines.append("    }")
        lines.append("}")

        let source = lines.joined(separator: "\n")
        try source.data(using: .utf8)?.write(to: mainSwift)
    }

    private static func scaffoldSeedTarget(in root: URL, cfg: Config) throws {
        let packageURL = root
            .appendingPathComponent("Packages/FountainApps/Package.swift", isDirectory: false)
        let fm = FileManager.default
        guard fm.fileExists(atPath: packageURL.path) else { return }

        var contents = try String(contentsOf: packageURL)
        if contents.contains("name: \"\(cfg.appId)-seed\"") {
            return
        }

        var lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let nameIndex = lines.firstIndex(where: { $0.contains("name: \"llm-chat-seed\"") }) else {
            return
        }
        guard nameIndex > 0 else { return }

        let execLineIndex = nameIndex - 1
        let execIndent = String(lines[execLineIndex].prefix { $0 == " " || $0 == "\t" })
        let paramIndent = execIndent + "    "

        let snippet: [String] = [
            "\(execIndent).executableTarget(",
            "\(paramIndent)name: \"\(cfg.appId)-seed\",",
            "\(paramIndent)dependencies: [",
            "\(paramIndent)    .product(name: \"FountainStoreClient\", package: \"FountainCore\"),",
            "\(paramIndent)    .product(name: \"LauncherSignature\", package: \"FountainCore\")",
            "\(paramIndent)],",
            "\(paramIndent)path: \"Sources/\(cfg.appId)-seed\"",
            "\(execIndent)),"
        ]

        lines.insert(contentsOf: snippet, at: execLineIndex)
        contents = lines.joined(separator: "\n")
        try contents.write(to: packageURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Phase 3: Test scaffolding (surface + PE + snapshot placeholders)

    private static func scaffoldTests(in root: URL, cfg: Config) throws {
        try scaffoldTestSources(in: root, cfg: cfg)
        try scaffoldTestTarget(in: root, cfg: cfg)
    }

    private static func scaffoldTestSources(in root: URL, cfg: Config) throws {
        let appIdCamel = camelCase(cfg.appId)
        let testsDir = root
            .appendingPathComponent("Packages/FountainApps/Tests", isDirectory: true)
            .appendingPathComponent("\(appIdCamel)Tests", isDirectory: true)
        let fm = FileManager.default
        let surfaceFile = testsDir.appendingPathComponent("\(appIdCamel)SurfaceTests.swift", isDirectory: false)
        if fm.fileExists(atPath: surfaceFile.path) {
            return
        }

        try fm.createDirectory(at: testsDir, withIntermediateDirectories: true)
        if cfg.visual {
            let baselinesDir = testsDir.appendingPathComponent("Baselines", isDirectory: true)
            try fm.createDirectory(at: baselinesDir, withIntermediateDirectories: true)
            let gitkeep = baselinesDir.appendingPathComponent(".gitkeep", isDirectory: false)
            if !fm.fileExists(atPath: gitkeep.path) {
                try Data().write(to: gitkeep)
            }
        }

        var lines: [String] = []
        let appId = cfg.appId
        lines.append("import XCTest")
        lines.append("")
        lines.append("@MainActor")
        lines.append("final class \(appIdCamel)SurfaceTests: XCTestCase {")
        lines.append("    func testPlaceholderSurface() {")
        lines.append("        // TODO: add FountainGUIKit surface tests for \(appId).")
        lines.append("        XCTAssertTrue(true)")
        lines.append("    }")
        lines.append("}")
        lines.append("")
        lines.append("@MainActor")
        lines.append("final class \(appIdCamel)PETests: XCTestCase {")
        lines.append("    func testPlaceholderPE() {")
        lines.append("        // TODO: add MIDI 2.0 PE tests for \(appId).")
        lines.append("        XCTAssertTrue(true)")
        lines.append("    }")
        lines.append("}")
        if cfg.visual {
            lines.append("")
            lines.append("@MainActor")
            lines.append("final class \(appIdCamel)SnapshotTests: XCTestCase {")
            lines.append("    func testPlaceholderSnapshots() {")
            lines.append("        // TODO: add FCIS-VRT Render snapshot tests for \(appId).")
            lines.append("        XCTAssertTrue(true)")
            lines.append("    }")
            lines.append("}")
        }

        let source = lines.joined(separator: "\n")
        try source.data(using: .utf8)?.write(to: surfaceFile)
    }

    private static func scaffoldTestTarget(in root: URL, cfg: Config) throws {
        let packageURL = root
            .appendingPathComponent("Packages/FountainApps/Package.swift", isDirectory: false)
        let fm = FileManager.default
        guard fm.fileExists(atPath: packageURL.path) else { return }

        let appIdCamel = camelCase(cfg.appId)
        var contents = try String(contentsOf: packageURL)
        if contents.contains("name: \"\(appIdCamel)Tests\"") {
            return
        }

        var lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let nameIndex = lines.firstIndex(where: { $0.contains("name: \"LLMChatAppTests\"") }) else {
            return
        }
        guard nameIndex > 0 else { return }

        let testLineIndex = nameIndex - 1
        let testIndent = String(lines[testLineIndex].prefix { $0 == " " || $0 == "\t" })
        let paramIndent = testIndent + "    "

        var snippet: [String] = [
            "\(testIndent).testTarget(",
            "\(paramIndent)name: \"\(appIdCamel)Tests\",",
            "\(paramIndent)dependencies: [],",
            "\(paramIndent)path: \"Tests/\(appIdCamel)Tests\""
        ]
        if cfg.visual {
            snippet.append("\(paramIndent),resources: [")
            snippet.append("\(paramIndent)    .process(\"Baselines\")")
            snippet.append("\(paramIndent)]")
        }
        snippet.append("\(testIndent)),")

        lines.insert(contentsOf: snippet, at: testLineIndex)
        contents = lines.joined(separator: "\n")
        try contents.write(to: packageURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Phase 4: Optional app surface target (FGK-based)

    private static func scaffoldApp(in root: URL, cfg: Config) throws {
        try scaffoldAppSources(in: root, cfg: cfg)
        try scaffoldAppTarget(in: root, cfg: cfg)
    }

    private static func scaffoldAppSources(in root: URL, cfg: Config) throws {
        let appDir = root
            .appendingPathComponent("Packages/FountainApps/Sources", isDirectory: true)
            .appendingPathComponent("\(cfg.appId)-app", isDirectory: true)
        let appMain = appDir.appendingPathComponent("AppMain.swift", isDirectory: false)
        let fm = FileManager.default
        if fm.fileExists(atPath: appMain.path) {
            return
        }
        try fm.createDirectory(at: appDir, withIntermediateDirectories: true)

        let appId = cfg.appId
        let appIdCamel = camelCase(appId)
        let stateType = "\(appIdCamel)SurfaceState"
        let viewType = "\(appIdCamel)SurfaceView"
        let targetType = "\(appIdCamel)InstrumentTarget"
        let delegateType = "\(appIdCamel)AppDelegate"
        let mainType = "\(appIdCamel)AppMain"

        var lines: [String] = []
        lines.append("import AppKit")
        lines.append("import FountainGUIKit")
        lines.append("import LauncherSignature")
        lines.append("")
        lines.append("struct \(stateType) {")
        lines.append("    var zoom: CGFloat = 1.0")
        lines.append("    var translation: CGPoint = .zero")
        lines.append("}")
        lines.append("")
        lines.append("@MainActor")
        lines.append("final class \(viewType): FGKRootView {")
        lines.append("    var state = \(stateType)()")
        lines.append("")
        lines.append("    override func draw(_ dirtyRect: NSRect) {")
        lines.append("        super.draw(dirtyRect)")
        lines.append("")
        lines.append("        guard let context = NSGraphicsContext.current?.cgContext else { return }")
        lines.append("")
        lines.append("        context.setFillColor(NSColor.windowBackgroundColor.cgColor)")
        lines.append("        context.fill(bounds)")
        lines.append("")
        lines.append("        context.saveGState()")
        lines.append("")
        lines.append("        let center = CGPoint(x: bounds.midX, y: bounds.midY)")
        lines.append("        context.translateBy(x: center.x + state.translation.x, y: center.y + state.translation.y)")
        lines.append("        context.scaleBy(x: state.zoom, y: state.zoom)")
        lines.append("")
        lines.append("        let rect = CGRect(x: -40.0, y: -40.0, width: 80.0, height: 80.0)")
        lines.append("        context.setFillColor(NSColor.systemBlue.cgColor)")
        lines.append("        context.fill(rect)")
        lines.append("")
        lines.append("        context.restoreGState()")
        lines.append("    }")
        lines.append("}")
        lines.append("")
        lines.append("@MainActor")
        lines.append("final class \(targetType): FGKEventTarget, FGKPropertyConsumer {")
        lines.append("    private unowned let view: \(viewType)")
        lines.append("    private let node: FGKNode")
        lines.append("")
        lines.append("    init(view: \(viewType), node: FGKNode) {")
        lines.append("        self.view = view")
        lines.append("        self.node = node")
        lines.append("    }")
        lines.append("")
        lines.append("    func handle(event: FGKEvent) -> Bool {")
        lines.append("        switch event {")
        lines.append("        case .scroll(let scroll):")
        lines.append("            applyPan(dx: CGFloat(scroll.deltaX), dy: CGFloat(scroll.deltaY))")
        lines.append("        case .magnify(let magnify):")
        lines.append("            applyZoom(factor: 1.0 + CGFloat(magnify.magnification))")
        lines.append("        default:")
        lines.append("            break")
        lines.append("        }")
        lines.append("        return true")
        lines.append("    }")
        lines.append("")
        lines.append("    func setProperty(_ name: String, value: FGKPropertyValue) {")
        lines.append("        switch (name, value) {")
        lines.append("        case (\"canvas.zoom\", .float(let v)):")
        lines.append("            view.state.zoom = CGFloat(min(max(v, 0.2), 5.0))")
        lines.append("        case (\"canvas.translation.x\", .float(let v)):")
        lines.append("            view.state.translation.x = CGFloat(v)")
        lines.append("        case (\"canvas.translation.y\", .float(let v)):")
        lines.append("            view.state.translation.y = CGFloat(v)")
        lines.append("        default:")
        lines.append("            break")
        lines.append("        }")
        lines.append("        view.needsDisplay = true")
        lines.append("    }")
        lines.append("")
        lines.append("    private func applyPan(dx: CGFloat, dy: CGFloat) {")
        lines.append("        let newX = Double(view.state.translation.x + dx)")
        lines.append("        let newY = Double(view.state.translation.y + dy)")
        lines.append("        _ = node.setProperty(\"canvas.translation.x\", value: .float(newX))")
        lines.append("        _ = node.setProperty(\"canvas.translation.y\", value: .float(newY))")
        lines.append("    }")
        lines.append("")
        lines.append("    private func applyZoom(factor: CGFloat) {")
        lines.append("        let current = Double(view.state.zoom)")
        lines.append("        let next = min(max(current * Double(factor), 0.2), 5.0)")
        lines.append("        _ = node.setProperty(\"canvas.zoom\", value: .float(next))")
        lines.append("    }")
        lines.append("}")
        lines.append("")
        lines.append("@MainActor")
        lines.append("private final class \(delegateType): NSObject, NSApplicationDelegate {")
        lines.append("    private var window: NSWindow?")
        lines.append("")
        lines.append("    func applicationDidFinishLaunching(_ notification: Notification) {")
        lines.append("        let contentSize = NSSize(width: 640, height: 400)")
        lines.append("        let frame = NSRect(origin: .zero, size: contentSize)")
        lines.append("")
        lines.append("        let properties: [FGKPropertyDescriptor] = [")
        lines.append("            .init(name: \"canvas.zoom\", kind: .float(min: 0.2, max: 5.0, default: 1.0)),")
        lines.append("            .init(name: \"canvas.translation.x\", kind: .float(min: -1000.0, max: 1000.0, default: 0.0)),")
        lines.append("            .init(name: \"canvas.translation.y\", kind: .float(min: -1000.0, max: 1000.0, default: 0.0))")
        lines.append("        ]")
        lines.append("")
        lines.append("        let rootNode = FGKNode(")
        lines.append("            instrumentId: \"\(cfg.agentId)\",")
        lines.append("            frame: frame,")
        lines.append("            properties: properties,")
        lines.append("            target: nil")
        lines.append("        )")
        lines.append("")
        lines.append("        let rootView = \(viewType)(frame: frame, rootNode: rootNode)")
        lines.append("        rootView.wantsLayer = true")
        lines.append("")
        lines.append("        let target = \(targetType)(view: rootView, node: rootNode)")
        lines.append("        rootNode.target = target")
        lines.append("")
        lines.append("        let window = NSWindow(")
        lines.append("            contentRect: frame,")
        lines.append("            styleMask: [.titled, .closable, .resizable],")
        lines.append("            backing: .buffered,")
        lines.append("            defer: false")
        lines.append("        )")
        lines.append("        window.title = \"\(appIdCamel) Instrument\"")
        lines.append("        window.contentView = rootView")
        lines.append("        window.center()")
        lines.append("        window.makeKeyAndOrderFront(nil)")
        lines.append("        window.makeFirstResponder(rootView)")
        lines.append("        NSApp.activate(ignoringOtherApps: true)")
        lines.append("        self.window = window")
        lines.append("    }")
        lines.append("}")
        lines.append("")
        lines.append("@main")
        lines.append("enum \(mainType) {")
        lines.append("    static func main() {")
        lines.append("        let env = ProcessInfo.processInfo.environment")
        lines.append("        if env[\"FOUNTAIN_SKIP_LAUNCHER_SIG\"] != \"1\" {")
        lines.append("            verifyLauncherSignature()")
        lines.append("        }")
        lines.append("        let app = NSApplication.shared")
        lines.append("        app.setActivationPolicy(.regular)")
        lines.append("        let delegate = \(delegateType)()")
        lines.append("        app.delegate = delegate")
        lines.append("        app.run()")
        lines.append("    }")
        lines.append("}")

        let source = lines.joined(separator: "\n")
        try source.data(using: .utf8)?.write(to: appMain)
    }

    private static func scaffoldAppTarget(in root: URL, cfg: Config) throws {
        let packageURL = root
            .appendingPathComponent("Packages/FountainApps/Package.swift", isDirectory: false)
        let fm = FileManager.default
        guard fm.fileExists(atPath: packageURL.path) else { return }

        var contents = try String(contentsOf: packageURL)
        if contents.contains("name: \"\(cfg.appId)-app\"") {
            return
        }

        var lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let nameIndex = lines.firstIndex(where: { $0.contains("name: \"llm-chat-app\"") }) else {
            return
        }
        guard nameIndex > 0 else { return }

        let execLineIndex = nameIndex - 1
        let execIndent = String(lines[execLineIndex].prefix { $0 == " " || $0 == "\t" })
        let paramIndent = execIndent + "    "

        let snippet: [String] = [
            "\(execIndent).executableTarget(",
            "\(paramIndent)name: \"\(cfg.appId)-app\",",
            "\(paramIndent)dependencies: [",
            "\(paramIndent)    .product(name: \"FountainGUIKit\", package: \"FountainGUIKit\"),",
            "\(paramIndent)    .product(name: \"LauncherSignature\", package: \"FountainCore\")",
            "\(paramIndent)],",
            "\(paramIndent)path: \"Sources/\(cfg.appId)-app\"",
            "\(execIndent)),"
        ]

        lines.insert(contentsOf: snippet, at: execLineIndex)
        contents = lines.joined(separator: "\n")
        try contents.write(to: packageURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Phase 5: Validation (facts seeding, lint, tests)

    private static func runValidationIfAvailable(in root: URL, cfg: Config) throws {
        let fm = FileManager.default
        let lintScript = root.appendingPathComponent("Scripts/instrument-lint.sh", isDirectory: false)
        let fountainAppsPackage = root.appendingPathComponent("Packages/FountainApps/Package.swift", isDirectory: false)
        let fountainToolingPackage = root.appendingPathComponent("Packages/FountainTooling/Package.swift", isDirectory: false)

        guard fm.fileExists(atPath: lintScript.path),
              fm.fileExists(atPath: fountainAppsPackage.path),
              fm.fileExists(atPath: fountainToolingPackage.path) else {
            // Likely running in a synthetic root (e.g. unit tests); skip validation.
            return
        }

        try runOpenAPIToFacts(in: root, cfg: cfg)
        try runInstrumentLint(in: root)
        try runAppTests(in: root, cfg: cfg)
    }

    private static func runOpenAPIToFacts(in root: URL, cfg: Config) throws {
        let specPath = root
            .appendingPathComponent("Packages/FountainSpecCuration/openapi/v1", isDirectory: true)
            .appendingPathComponent(cfg.specName, isDirectory: false)
            .path
        try runCommand(
            tool: "swift",
            arguments: [
                "run",
                "--package-path", "Packages/FountainTooling",
                "-c", "debug",
                "openapi-to-facts",
                specPath,
                "--agent-id", cfg.agentId,
                "--seed",
                "--allow-tools-only"
            ],
            in: root,
            extraEnv: [
                "FOUNTAINSTORE_DIR": ".fountain/store",
                "CORPUS_ID": "agents"
            ]
        )
    }

    private static func runInstrumentLint(in root: URL) throws {
        let scriptPath = root
            .appendingPathComponent("Scripts/instrument-lint.sh", isDirectory: false)
            .path
        try runCommand(
            tool: "bash",
            arguments: [scriptPath],
            in: root,
            extraEnv: [
                "FOUNTAINSTORE_DIR": ".fountain/store"
            ]
        )
    }

    private static func runAppTests(in root: URL, cfg: Config) throws {
        let appIdCamel = camelCase(cfg.appId)
        try runCommand(
            tool: "swift",
            arguments: [
                "test",
                "--package-path", "Packages/FountainApps",
                "-c", "debug",
                "--filter", "\(appIdCamel)Tests"
            ],
            in: root,
            extraEnv: [:]
        )
    }

    private static func runCommand(tool: String, arguments: [String], in directory: URL, extraEnv: [String: String]) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [tool] + arguments
        proc.currentDirectoryURL = directory
        var env = ProcessInfo.processInfo.environment
        for (k, v) in extraEnv {
            env[k] = v
        }
        proc.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardOutput = stdout
        proc.standardError = stderr

        try proc.run()
        proc.waitUntilExit()

        guard proc.terminationStatus == 0 else {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errData, encoding: .utf8) ?? ""
            throw NSError(
                domain: "instrument-new",
                code: Int(proc.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: "command failed: \(tool) \(arguments.joined(separator: " "))\n\(message)"
                ]
            )
        }
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
