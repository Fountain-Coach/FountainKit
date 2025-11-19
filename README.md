# FountainKit Workspace

FountainKit is the Swift Package Manager workspace that powers FountainAI for the Fountain Coach organization. It breaks the original monolith into focused Swift packages for runtime, services, tools, specs, and apps so they can evolve, test, and ship independently.

At a high level, the workspace ties together:
- an **execution plane** for MIDI 2.0 instruments and UI surfaces,
- a **spec/control plane** built on OpenAPI (services, tools, clients),
- and a **memory plane** backed by FountainStore (prompts, facts, indexes).

Read next (orientation):
- `ONBOARDING.md` — 10‑minute quickstart with dev scripts and conventions.
- `docs/Book-of-FountainAI-Plain.md` — plain‑language overview of the system.
- `docs/Book-of-FountainAI.md` — technical tour of packages, services, and flows.
- `docs/bye-bye-coremidi.md` — why CoreMIDI is deprecated and how MIDI 2.0 replaces it.

## Quick start

### Bring up the stack

- Start core services (gateway, planner, function‑caller, persist, awareness, bootstrap) with readiness checks:
  - `Scripts/dev/dev-up --check`
  - or `Scripts/fk up`
- See what is running:
  - `Scripts/dev/dev-status`
  - or `Scripts/fk status`
- Stop everything:
  - `Scripts/dev/dev-down --force`
  - or `Scripts/fk down`

By default, `dev-up` also launches the **Baseline‑PatchBay** UI, which is the canonical baseline for instrument behaviour and robot testing.

### Launch key apps

- Baseline‑PatchBay UI:
  - `Scripts/apps/baseline-patchbay`
  - Web mirror: `Scripts/apps/baseline-patchbay-web`
- MIDI 2.0 HTTP bridge (UMP send/record + headless instruments):
  - `Scripts/apps/midi-service`
- Tools Factory and Tool Server:
  - `Scripts/dev/tools-factory-min run`
  - `Scripts/dev/tool-server-min run`

### Helper CLI (`fk`)

- `Scripts/fk doctor` — verify `swift`, `docker`, `jq`, `curl`.
- `Scripts/fk build` — build the workspace (`swift build`).
- `Scripts/fk up` / `Scripts/fk down` — start/stop core services.
- `Scripts/fk status` — show status, including Tool Server.
- `Scripts/fk open list` / `--json` — list service endpoints and ports.
- `Scripts/fk open schema <target>` — open `/openapi.yaml` for a service.
- `Scripts/fk baseline` — launch the Baseline‑PatchBay UI.
- `Scripts/fk ts-api exiftool -- -ver` — call Tool Server API helpers.

## Service map

Core (started by `Scripts/dev/dev-up` or `Scripts/dev-up`):
- `gateway-server` — port `8010` — readiness: `GET /metrics` (JSON)
- `baseline-awareness-server` — port `8001` — readiness: `GET /metrics`
- `bootstrap-server` — port `8002` — readiness: `GET /metrics`
- `planner-server` — port `8003` — readiness: `GET /metrics`
- `function-caller-server` — port `8004` — readiness: `GET /metrics`
- `persist-server` — port `8005` — readiness: `GET /metrics`

Extras (started by `Scripts/dev/dev-up --all` or `Scripts/dev-up --all`):
- `tools-factory-server` — port `8011` — readiness: `GET /metrics`
- `tool-server` — port `8012` — readiness: `GET /_health` (200) or `GET /metrics`
- `semantic-browser-server` — port `8007` — readiness: `GET /metrics` (or `GET /v1/health`) — built in its own package `FountainApps-SemanticBrowser`
- `publishing-frontend` — config-driven port — readiness: via upstream gateway plugin

### Fast local servers

- One-shot convenience: `Scripts/dev-servers-up.sh` prebuilds required server binaries and starts them with readiness checks.
  - Flags: `--no-extras` (core only), `--release` (build/run release configuration).
- Manual prebuild: `bash Scripts/dev-up prebuild --all` (or set `DEV_UP_CONFIGURATION=release`).
- Start with checks: `DEV_UP_USE_BIN=1 DEV_UP_CHECKS=1 bash Scripts/dev-up --all`.

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
| `Evaluation of FountainAI Monolith Refactoring into **FountainKit**.pdf` | Architectural write‑up describing the rationale and migration plan. |

## Package overview

| Package | Description |
| ------- | ----------- |
| `FountainCore` | Networking/runtime primitives, FountainStore client, launcher signature, resource utilities, and shared AI adapters. |
| `FountainAPIClients` | OpenAPI‑driven REST clients and Tutor Dashboard domain models layered on `FountainCore`. |
| `FountainGatewayKit` | Persona orchestrator, gateway plugins, and publishing frontend for the control plane. |
| `FountainServiceKit-<Service>` | Service libraries for planner, function caller, bootstrap, awareness, persist, tools factory, and tool server. |
| `FountainTelemetryKit` | MIDI 2.0 streaming models, transports, and SSE/MIDI diagnostics (`flexctl`). |
| `FountainTooling` | OpenAPI curator tools, facts generator, instrument scaffolding/linting, and related services. |
| `FountainApps` | Executable entry points (gateway server, service daemons, tutor dashboard CLI, macOS launcher, MIDI instruments host). |
| `FountainApps-SemanticBrowser` | Standalone package containing the `semantic-browser-server` executable. |
| `FountainSpecCuration` | Authoritative OpenAPI specs, fixtures, and regeneration scripts. |
| `FountainExamples` | Sample integrations and showcase applications using the modular kits. |

Each package lives under `Packages/<Name>` with its own `Package.swift`, `Sources/`, `Tests/`, and README. The root manifest depends on these packages via relative paths for local development.

### Tooling quick reference

| Tool / Target | Location | Purpose |
| ------------- | -------- | ------- |
| `openapi-curator-cli` | `Packages/FountainTooling/Sources/openapi-curator-cli` | CLI wrapper over the curator engine; curates OpenAPI specs and computes truth tables. |
| `openapi-curator-service` | `Packages/FountainTooling/Sources/openapi-curator-service` | HTTP service exposing `/curate`, `/truth-table`, and `/metrics` for automated spec curation. |
| `openapi-to-facts` | `Packages/FountainTooling/Sources/openapi-to-facts` | Converts OpenAPI specs into MIDI‑CI Property Exchange facts and optionally seeds FountainStore. |
| `instrument-lint` | `Packages/FountainTooling/Sources/instrument-lint` | Lints instruments against specs, facts, and `Tools/instruments.json` (structure and coverage checks). |
| `instrument-new` | `Packages/FountainTooling/Sources/instrument-new` | Scaffolds new instruments (spec stub, facts mapping, instrument index entry, seed target, tests, optional app). |
| `instrument-new-service-server` | `Packages/FountainTooling/Sources/instrument-new-service-server` | HTTP wrapper around `instrument-new` (see `Packages/FountainSpecCuration/openapi/v1/instrument-new.yml`). |
| `flexctl` | `Packages/FountainTelemetryKit/Sources/flexctl` | MIDI/SSE diagnostics console for telemetry troubleshooting. |
| `gateway-server` | `Packages/FountainApps/Sources/gateway-server` | Gateway for persona orchestration, tool invocation, and publishing. |
| `tools-factory-server` | `Packages/FountainApps/Sources/tools-factory-server` | Tools Factory: generates tools and facts from OpenAPI and serves `/agent-facts` and `/agent-secrets` helpers. |
| `tool-server` | `Packages/FountainApps/Sources/tool-server` | Sandbox that executes tools via Docker; managed by `Scripts/toolserver` and `Scripts/fk`. |
| `teatro-examples` | `Packages/FountainExamples/Sources` | Runnable examples showing how downstream apps integrate with FountainKit APIs. |
| `Scripts/openapi/openapi-to-facts.sh` | `Scripts/openapi` | Iterates `Tools/openapi-facts-mapping.json` and seeds facts for all mapped agents. |
| `Scripts/instrument-lint.sh` | `Scripts` | Convenience wrapper that runs `instrument-lint` across the instrument index. |
| `Scripts/renew-certs.sh` | `Scripts` | Rotates TLS certificates and uploads them to managed environments. |
| `Scripts/start-diagnostics.swift` | `Scripts` | Boots SSE/MIDI diagnostics pipelines backed by telemetry kits. |

## OpenAPI specifications

Authoritative OpenAPI documents live in `Packages/FountainSpecCuration/openapi`. Service executables include README files that link directly to their specs (for example `Packages/FountainSpecCuration/openapi/v1/planner.yml`). Use this directory when regenerating clients or browsing HTTP contracts—the legacy root‑level `openapi/` tree has been removed.

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

### Run cross‑package examples

```bash
swift run --package-path Packages/FountainExamples hello-fountainai-teatro
```

The executable seeds an in‑memory FountainStore and routes a request through the gateway, planner, and function‑caller services, providing integration coverage alongside the package tests.

### Launch the Baseline UI (recommended for local UI runs)

Baselined UI for instrument development and robot testing:

```bash
# Start core services and auto‑launch the baseline UI
Scripts/dev/dev-up --check

# Or launch the UI directly
Scripts/apps/baseline-patchbay
```

The baseline UI speaks MIDI 2.0 for Canvas/Grid/Viewport/Cursor, exposes App‑level PE for `canvas.reset`, and includes a MIDI monitor that fades on idle and wakes on activity.

### Semantic Browser server (standalone package)

- Build:
  - `swift build --package-path Packages/FountainApps-SemanticBrowser`
- Run:
  - `swift run --package-path Packages/FountainApps-SemanticBrowser semantic-browser-server`
- Shortcut helper:
  - `Scripts/semantic-browser build` or `Scripts/semantic-browser run`

## Development workflow

- **Pick the right package:** runtime‑level changes live in `FountainCore`, service logic in its `FountainServiceKit-<Service>`, telemetry work in `FountainTelemetryKit`, etc.
- **Update manifests:** update the relevant `Package.swift` when adding products, dependencies, or resources.
- **Document public APIs:** add docs in package READMEs and doc comments; note capability requirements and threading expectations.
- **Regenerate clients/facts:** use the OpenAPI tools in `FountainTooling` (`openapi-curator-*`, `openapi-to-facts`) whenever specs change.
- **Keep dependencies acyclic:** higher‑level kits may depend on `FountainCore` and peer kits, but never in reverse.

## Contributing

- Follow the engineering guide in `AGENTS.md`.
- Ensure `swift build` and package‑specific `swift test` succeed before opening PRs.
- Update deployment manifests, Dockerfiles, and scripts to reference the new package paths when services move.
- Tag releases per package so downstream consumers can track API changes.

## License

FountainKit inherits the licensing terms of the original FountainAI project; consult the repository’s `LICENSES/` directory for details.

