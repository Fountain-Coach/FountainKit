import Foundation
import FountainStoreClient

@main
struct ServiceMinimalSeedMain {
    static func main() async {
        let appId = "service-minimal" // Corpus and page prefix: prompt:service-minimal

        let prompt = """
        Service‑Minimal Targeted Builds (Teatro Prompt)

        What
        - Keep the manifest stable. Do not gate the entire workspace; instead, build just one service target.
        - Move OpenAPI generation into a <service>-service-core library target; server depends on this core and has no generator plugin.
        - Filter generation to that service’s routes via openapi-generator-config.yaml.
        - Thin server: only wires transports and registers generated handlers. No embedded smoke testing.
        - Targeted builds via SwiftPM: `swift build --package-path Packages/FountainApps -c debug --target <service>-service-server`.
        - Wrapper scripts per service (optional): provide `build|run` only; no `smoke` subcommand.

        Why
        - Faster builds: generator runs once per service in a library; the server’s compile graph stays small.
        - Safer: OpenAPI remains curated under FountainSpecCuration; no duplicated specs in servers.
        - Non‑destructive: full manifest remains intact; pattern is per‑service and opt‑in.

        How (example: fountain‑editor)
        - Core: `Packages/FountainApps/Sources/fountain-editor-service` (owns `openapi.yaml` symlink and generator config; exports APIProtocol).
        - Server: `Packages/FountainApps/Sources/fountain-editor-service-server` (depends on core + FountainRuntime; no plugin/spec).
        - Build: `swift build --package-path Packages/FountainApps -c debug --target fountain-editor-service-server`.

        Extend to other services
        - gateway‑server, pbvrt‑server, quietframe‑service‑server
        - planner‑server, function‑caller‑server, persist‑server, baseline‑awareness‑server, bootstrap‑server, tools‑factory‑server, tool‑server
        - For each: create <service>-service core with spec+plugin+filters; make server depend on it; add a thin wrapper script.

        Invariants
        - Manifest stable; no monorepo‑wide gating.
        - OpenAPI generator only in core targets; servers never declare the plugin.
        - No smoke test codepaths in server mains; real HTTP servers only.
        """

        let facts: [String: Any] = [
            "corpus": [
                "id": appId,
                "page": "prompt:\(appId)"
            ],
            "pattern": [
                "manifest_stable": true,
                "core_owns_openapi_generation": true,
                "server_has_no_generator_plugin": true,
                "no_smoke_in_server_main": true
            ],
            "services": [
                "fountain-editor": "adopted",
                "gateway": "planned",
                "pbvrt": "planned",
                "quietframe-service": "planned",
                "planner": "planned",
                "function-caller": "planned",
                "persist": "planned",
                "baseline-awareness": "planned",
                "bootstrap": "planned",
                "tools-factory": "planned",
                "tool-server": "planned"
            ],
            "commands": [
                "build_single": "swift build --package-path Packages/FountainApps -c debug --target <service>-service-server",
                "run_single": "FOUNTAIN_SKIP_LAUNCHER_SIG=1 swift run --package-path Packages/FountainApps <service>-service-server",
                "seed_prompt": "Scripts/apps/service-minimal-seed"
            ]
        ]

        await PromptSeeder.seedAndPrint(appId: appId, prompt: prompt, facts: facts)
    }
}

