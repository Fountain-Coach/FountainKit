import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct ServiceMinimalSeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }

        let corpusId = env["CORPUS_ID"] ?? "build-profiles"
        let store: FountainStoreClient = {
            if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
                let url: URL
                if dir.hasPrefix("~") {
                    url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true)
                } else { url = URL(fileURLWithPath: dir, isDirectory: true) }
                if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
            }
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) { return FountainStoreClient(client: disk) }
            return FountainStoreClient(client: EmbeddedFountainStoreClient())
        }()

        do { _ = try await store.createCorpus(corpusId, metadata: ["kind": "build-patterns"]) } catch { }

        let pageId = "prompt:service-minimal"
        let page = Page(corpusId: corpusId, pageId: pageId, url: "store://prompt/service-minimal", host: "store", title: "Service‑Minimal Build Pattern (Prompt)")
        _ = try? await store.addPage(page)

        // Teatro prompt — authoritative description (kept terse; human-first, machine-usable)
        let prompt = """
        Service‑Minimal Build Pattern

        What
        - Per‑service targeted builds via manifest gating and single‑source OpenAPI generation.
        - Each service has a <service>-service core owning OpenAPI generator; <service>-server executable depends on the core and FountainRuntime.

        Why
        - Cold builds and incremental edits become fast and deterministic by avoiding unrelated packages and duplicate generator runs.
        - Keeps iteration focused; enables small wrapper scripts for build/run/smoke.

        How
        - Env gates: FK_MIN_TARGET=<service> (or FK_<SERVICE>_MINIMAL=1), FK_SKIP_NOISY_TARGETS=1, FOUNTAIN_SKIP_LAUNCHER_SIG=1.
        - Manifest gating: when gated, products/dependencies/targets include only the selected service core+server and minimal external deps (FountainCore + Apple OpenAPI libs).
        - OpenAPI: generator plugin/config lives in the core target with filter.paths for the service routes; server has no plugin/spec and may serve the core spec as a fallback.
        - Scripts: Scripts/dev/<service>-min [build|run|smoke] export the env and operate only that target.

        Invariants (must hold)
        - Generator runs exactly once (in core); server never attaches the plugin.
        - Minimal deps omit heavy stacks unless explicitly required by the service.
        - Wrapper scripts always export FK_SKIP_NOISY_TARGETS=1 and FOUNTAIN_SKIP_LAUNCHER_SIG=1 for dev.
        - Specs are authoritative under FountainSpecCuration or the service core; no generated files are committed.

        Where
        - Manifest gating: Packages/FountainApps/Package.swift
        - Editor reference wrapper: Scripts/dev/editor-min
        - Store page: prompt:service-minimal (this page)
        """
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):teatro", pageId: pageId, kind: "teatro.prompt", text: prompt))

        // Facts JSON for quick machine consumption
        let facts: [String: Any] = [
            "kind": "build-pattern",
            "id": "service-minimal",
            "store": ["corpus": corpusId, "page": pageId, "teatro": "\(pageId):teatro", "facts": "\(pageId):facts"],
            "env_flags": ["FK_MIN_TARGET", "FK_<SERVICE>_MINIMAL", "FK_SKIP_NOISY_TARGETS", "FOUNTAIN_SKIP_LAUNCHER_SIG"],
            "openapi": ["owned_by": "core", "server_has_plugin": false, "filters": true],
            "manifest": ["gated": true, "products_minimal": true, "deps_minimal": true],
            "wrappers_pattern": "Scripts/dev/<service>-min",
            "baseline_reference": "Scripts/dev/editor-min",
            "services_targeted": ["gateway", "pbvrt", "quietframe", "planner", "function-caller", "persist", "baseline-awareness", "bootstrap", "tools-factory", "tool-server"]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]), let s = String(data: data, encoding: .utf8) {
            _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):facts", pageId: pageId, kind: "facts", text: s))
        }
        print("Seeded Service‑Minimal Build Pattern → corpus=\(corpusId) page=\(pageId)")
    }
}

