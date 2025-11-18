import Foundation
import FountainStoreClient

/// Scaffold a new instrument according to Plans/instrument-new-plan.md.
///
/// This first implementation only parses arguments and prints what it would
/// create; it does not modify the tree yet. It exists to lock in the CLI shape
/// and allow future automated scaffolding.
@main
struct InstrumentNew {
    struct Config {
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
            describePlannedArtifacts(cfg)
        } catch {
            fputs("instrument-new error: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func parseConfig() throws -> Config {
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
        print("[instrument-new] This version only reports the planned artifacts.")
        print("                 Future revisions will create and wire them automatically.")
    }
}

