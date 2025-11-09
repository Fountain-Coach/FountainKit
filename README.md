# FountainKit Workspace

FountainKit is the Swift Package Manager workspace that powers FountainAI for the Fountain Coach GitHub organization. It decomposes the original monolithic package into focused modules that can evolve, test, and ship independently.

See ONBOARDING.md for a 10‑minute quickstart with dev scripts.

Related reading
- docs/blog/bye-bye-coremidi.md: Why we removed CoreMIDI, what replaces it (Loopback + MIDI 2.0 RTP/BLE), and how this improves determinism and CI.

Quick dev helpers:
- `Scripts/dev-up` – start core services (use `--check` for readiness)
- `Scripts/dev-down` – stop services (use `--force` to clear ports)
- `Scripts/dev-status` – show service/port/PID status at a glance
- `Scripts/dev-servers-up.sh` – prebuild all servers, then start with readiness checks (`--no-extras`, `--release`)
 - `Scripts/apps/baseline-patchbay` – launch the Baseline‑PatchBay UI (grid‑only baseline)
 - `Scripts/apps/baseline-patchbay-web` – launch the external Baseline‑PatchBay mirror (Vite, MIDI‑driven)
 - `Scripts/apps/midi-service` – start the MIDI 2.0 HTTP bridge (UMP send/record + headless instruments)

Quickstart (fk)
- `Scripts/fk doctor` — verify swift, docker, jq, curl
- `Scripts/fk init` — generate/update Tool Server `.env`
- `Scripts/fk build` — build the entire workspace
- `Scripts/fk up` / `Scripts/fk down` — start/stop core services
- `Scripts/fk status` — show status incl. Tool Server
- `Scripts/fk open tool-server` — open Tool Server `/_status`
- `Scripts/fk open schema tool-server` — open Tool Server `/openapi.yaml`
- `Scripts/fk open schema planner` — open Planner `/openapi.yaml` (works for most services)
- `Scripts/fk open list` — print ports and URLs for all targets
- `Scripts/fk open list --json` — output JSON array of target endpoints
- `Scripts/fk ts-api exiftool -- -ver` — call Tool Server API helpers

## Service Map

Core (started by `Scripts/dev-up`):
- gateway-server — port 8010 — readiness: GET `/metrics` (JSON)
- baseline-awareness-server — port 8001 — readiness: GET `/metrics`
- bootstrap-server — port 8002 — readiness: GET `/metrics`
- planner-server — port 8003 — readiness: GET `/metrics`
- function-caller-server — port 8004 — readiness: GET `/metrics`
- persist-server — port 8005 — readiness: GET `/metrics`

Extras (started by `Scripts/dev-up --all`):
- tools-factory-server — port 8011 — readiness: GET `/metrics`
- tool-server — port 8012 — readiness: GET `/_health` (200) or `/metrics`
- semantic-browser-server — port 8007 — readiness: GET `/metrics` (or `/v1/health`) — now built in its own package `FountainApps-SemanticBrowser`
- publishing-frontend — config-driven port — readiness: via upstream gateway plugin

### Fast local servers

- One-shot convenience: `Scripts/dev-servers-up.sh` prebuilds required server binaries and starts them with readiness checks.
  - Flags: `--no-extras` (core only), `--release` (build/run release configuration).
- Manual prebuild: `bash Scripts/dev-up prebuild --all` (or set `DEV_UP_CONFIGURATION=release`).
- Start with checks: `DEV_UP_USE_BIN=1 DEV_UP_CHECKS=1 bash Scripts/dev-up --all`.
- Launch MemChat app: `bash Scripts/launch-memchat-app.sh`.

## Repository layout

| Path | Purpose |
| ---- | ------- |
| `AGENTS.md` | Engineering guide and repository-wide conventions for coding, testing, and reviews. |
| `Configuration/` | Runtime configuration files consumed by services (gateway, role guard, curator, publishing, tutor dashboard). |
| `Packages/` | Swift packages that make up the modular workspace—each has its own manifest, sources, tests, and documentation. |
| `Public/` | Static assets served by HTTP frontends (health probes, landing page, styles). |
| `Scripts/` | Operational scripts for launching tooling, renewing certificates, and starting diagnostics. |
| `Workspace/` | Empty Xcode workspace placeholder used when generating IDE projects. |
| `Package.swift` / `Package.resolved` | Root SwiftPM manifest and lockfile aggregating all local packages. |
| `README.md` | This quick reference to help navigate the workspace. |
| `Evaluation of FountainAI Monolith Refactoring into **FountainKit**.pdf` | Architectural write-up describing the rationale and migration plan. |

## Package overview

| Package | Description |
| ------- | ----------- |
| `FountainCore` | Networking/runtime primitives, FountainStore client, launcher signature, resource utilities, and shared AI adapters. |
| `FountainAPIClients` | OpenAPI-driven REST clients and Tutor Dashboard domain models layered on `FountainCore`. |
| `FountainGatewayKit` | Persona orchestrator, gateway plugins, and publishing frontend for the control plane. |
| `FountainServiceKit-<Service>` | Service libraries for planner, function caller, bootstrap, awareness, persist, tools factory, and tool server. |
| `FountainTelemetryKit` | MIDI 2.0 streaming models, transports, and SSE/MIDI diagnostics (`flexctl`). |
| `FountainTooling` | OpenAPI curator CLI/service, client generator, SSE client, and GUI diagnostics tools. |
| `FountainApps` | Executable entry points (gateway server, service daemons, tutor dashboard CLI, macOS launcher). |
| `FountainApps-SemanticBrowser` | Standalone package containing the `semantic-browser-server` executable. |
| `FountainSpecCuration` | Authoritative OpenAPI specs, fixtures, and regeneration scripts. |
| `FountainExamples` | Sample Teatro integrations and showcase applications using the modular kits. |

Each package lives under `Packages/<Name>` with its own `Package.swift`, `Sources/`, `Tests/`, and README. The root manifest depends on these packages via relative paths for local development.

### Tooling quick reference

| Tool / Target | Location | Purpose |
| ------------- | -------- | ------- |
| `openapi-curator-cli` | `Packages/FountainTooling/Sources/openapi-curator-cli` | CLI wrapper over the curator engine; curates OpenAPI specs, computes diffs, and optionally submits to Tools Factory. |
| `openapi-curator-service` | `Packages/FountainTooling/Sources/openapi-curator-service` | Long-running HTTP service that exposes `/curate`, `/truth-table`, and `/metrics` endpoints for automated spec curation. |
| `fountain-client-generator` | `Packages/FountainTooling/Sources/fountain-client-generator` | Generates REST clients from curated specs and publishes them into `FountainAPIClients`. |
| `flexctl` | `Packages/FountainTelemetryKit/Sources/flexctl` | MIDI/SSE diagnostics console for telemetry troubleshooting. |
| `gateway-server` | `Packages/FountainApps/Sources/gateway-server` | Assembled executable that fronts persona orchestration, tool invocation, and publishing pipelines. |
| `tools-factory-server` | `Packages/FountainApps/Sources/tools-factory-server` | HTTP surface that receives curated specs, persists them, and coordinates downstream toolchain updates. |
| `teatro-examples` | `Packages/FountainExamples/Sources` | Collection of runnable examples showing how downstream apps integrate with FountainKit APIs. |
| `Scripts/renew-certs.sh` | `Scripts` | Helper script for rotating TLS certificates and uploading to managed environments. |
| `Scripts/start-diagnostics.swift` | `Scripts` | Swift script that boots SSE/MIDI diagnostics pipelines backed by telemetry kits. |

## OpenAPI specifications

Authoritative OpenAPI documents live in [`Packages/FountainSpecCuration/openapi`](Packages/FountainSpecCuration/openapi). Service executables include README files that link directly to their specs (for example `Packages/FountainSpecCuration/openapi/v1/planner.yml`). Use this directory when regenerating clients or browsing HTTP contracts—the legacy root-level `openapi/` tree has been removed.

## Getting started

### Bootstrap the workspace
```bash
swift build
```

### Run targeted tests

```bash
swift test --package-path Packages/FountainCore
swift test --package-path Packages/FountainGatewayKit
swift test --package-path Packages/FountainTelemetryKit
swift test --package-path Packages/FountainExamples
```

### Launch the gateway server (assembled from kits)

```bash
swift run --package-path Packages/FountainApps gateway-server
```

### Run cross-package examples

```bash
swift run --package-path Packages/FountainExamples hello-fountainai-teatro
```

The executable seeds an in-memory Fountain Store and routes a request through
the gateway, planner, and function-caller services, providing integration
coverage alongside the package tests.

### Semantic Browser server (standalone package)

- Build:
  - `swift build --package-path Packages/FountainApps-SemanticBrowser`
- Run:
  - `swift run --package-path Packages/FountainApps-SemanticBrowser semantic-browser-server`
- Shortcut helper:
  - `Scripts/semantic-browser build` or `Scripts/semantic-browser run`

## Development workflow

* **Pick the right package:**
  Runtime-level changes live in `FountainCore`, service logic in its `FountainServiceKit-<Service>`, telemetry work in `FountainTelemetryKit`, etc.

* **Update manifests:**
  Update the relevant `Package.swift` when adding products, dependencies, or resources.

* **Document public APIs:**
  Add docs in package READMEs and doc comments; note capability requirements and threading expectations.

* **Regenerate clients:**
  Use the `openapi-curator-cli` in `FountainTooling` whenever specs change.

* **Keep dependencies acyclic:**
  Higher-level kits may depend on `FountainCore` and peer kits, but never in reverse.

## Contributing

* Follow the engineering guide in `AGENTS.md`.
* Ensure `swift build` and package-specific `swift test` succeed before opening PRs.
* Update deployment manifests, Dockerfiles, and scripts to reference the new package paths when services move.
* Tag releases per package so downstream consumers can track API changes.

## License

FountainKit inherits the licensing terms of the original FountainAI project; consult the repository’s `LICENSES/` directory for details.
### Launch the Baseline UI (recommended for local UI runs)

Baselined UI for instrument development and robot testing:

```bash
# Start core services and auto-launch the baseline UI
Scripts/dev/dev-up --check

# Or launch the UI directly
Scripts/apps/baseline-patchbay
```

The baseline UI speaks MIDI 2.0 for Canvas/Grid/Viewport/Cursor, exposes App‑level PE for `canvas.reset`, and includes a MIDI monitor that fades on idle and wakes on activity. PE knobs for monitor fade and reset UI are available.
