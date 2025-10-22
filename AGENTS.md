# FountainKit — Agent Guide (Unified Master Plan inside)

Welcome to FountainKit, the modular SwiftPM workspace for the Fountain Coach organization (Contexter). The repository is split into local packages under `Packages/`:

- `FountainCore`: Runtime primitives, store client, adapters, launcher signature, resource helpers.
- `FountainAPIClients`: Generated OpenAPI clients and Tutor Dashboard models built on `FountainCore`.
- `FountainGatewayKit`: Gateway persona orchestrator, security/budget plugins, publishing frontend, and shared gateway utilities.
- `FountainServiceKit-<Service>`: Service libraries (planner, function-caller, bootstrap, awareness, persist, tools factory, tool server) with their helpers.
- `FountainTelemetryKit`: MIDI 2.0 streaming stack (`MIDI2*`, `SSEOverMIDI`, `FlexBridge`, `flexctl`) and related diagnostics.
- `FountainTooling`: OpenAPI curator CLI/service, spec validation helpers, diagnostics, GUI tooling.
- `FountainApps`: Executable entry points (servers, CLIs, macOS launchers) that stitch the kits together.
- `FountainApps-SemanticBrowser`: Standalone package containing the `semantic-browser-server` executable. See `Packages/FountainApps-SemanticBrowser/AGENTS.md` for package-specific guidance.
- `FountainSpecCuration`: Canonical OpenAPI specs, fixtures, and regeneration scripts shared across packages.
- `FountainExamples`: Sample apps and Teatro integrations that consume the published packages.

### Plans Index
- Unified Master Plan — embedded below in this file (authoritative).
- Studio plan — `Packages/FountainApps/Sources/FountainLauncherUI/AGENTS.md` (Control workspace).
- AudioTalk plan — `Packages/FountainServiceKit-AudioTalk/AGENTS.md` (service track).
- Spec curation norms — `Packages/FountainSpecCuration/openapi/AGENTS.md`.
- Scripts lifecycle — `Scripts/AGENTS.md`.

## OpenAPI-first development
- Every HTTP surface must have an authoritative OpenAPI document in `Packages/FountainSpecCuration/openapi`. Update specs *before* writing server or client code.
- Specs are versioned (`openapi/v{major}/service-name.yml`) and curated via the FountainAI OpenAPI Curator. Keep the curator output as the single source of truth and follow `Packages/FountainSpecCuration/openapi/AGENTS.md` for directory rules.
- Treat OpenAPI schema changes like code changes: include them in reviews, mention owning teams, and cite them in changelog/PR descriptions.

## Swift OpenAPI Generator workflow
- We standardise on Apple’s `OpenAPIGeneratorPlugin` plus `swift-openapi-runtime`. Running `swift build` generates clients, server stubs, and types—never commit generated output.
- Each target that exposes or consumes an API must provide:
  - `openapi.yaml` in its source directory (or a symlink into `FountainSpecCuration`).
  - `openapi-generator-config.yaml` declaring `generate: [types, client]` or `generate: [types, server]` (and `filter.paths` when scoping operations).
  - Transport implementations wired through `FountainCore` abstractions. Prefer SwiftNIO-based transports for servers; use URLSession or AsyncHTTPClient transports for clients.
- Move shared models into `FountainCore` and configure generators to omit duplicate schema emission.
- Regenerate by running `swift build` (root or package scoped). Do **not** hand-edit generated Swift files.

## Coding standards
- Target Swift 6.1; mark public APIs as `Sendable` when feasible.
- Use dependency injection across package seams—libraries must not reach into executable-only code.
- Keep dependency declarations in `Package.swift` alphabetised.
- Do not duplicate shared types; centralise cross-package models in `FountainCore` (or another shared kit) and document dependencies.
- Maintain doc comments for public APIs, including threading and capability expectations.

## Workflow expectations
1. Start with the spec: update `openapi.yaml` + config, run the curator, and lint specs locally (`Scripts/openapi-lint.sh` when available).
2. Implement or adjust transports and protocol conformances in Swift packages after regeneration.
3. Run `swift build` at the repository root to trigger generator output and ensure targets compile.
4. Run focused tests with `swift test --package-path Packages/<PackageName>`; every touched package must have green tests before PRs merge. Telemetry changes must cover `FountainTelemetryKit`.
5. Update package manifests when adding/removing targets or dependencies. Ensure client/server targets declare the generator plug-in and runtime dependencies.

## Continuous integration
- `CI` workflow: lint OpenAPI specs, run a full `swift build`, and fan out `swift test --package-path Packages/<Package>` across a matrix of packages on Xcode 16 runners.
- `CI Smoke`: boots core services via `Scripts/ci-smoke.sh`, probes readiness endpoints, and uploads logs for diagnostics.
- Both workflows require the tree to build without uncommitted generated sources. Failing lint or build steps block merges.

## Review checklist
- Specs are updated, linted, and referenced from targets (config files committed alongside code changes).
- Builds succeed (`swift build`) and all affected package tests pass.
- No cross-package `@testable import`.
- Gateway/service packages reference OpenAPI specs and configuration strictly through `FountainCore` abstractions.
- Executables in `FountainApps` import only the kits they need.
- Generated Swift files remain untouched; transport abstractions live in shared kits.

Thank you for helping FountainKit stay modular and healthy!

---

### Agents
- Legacy Studio (deprecated) — learnings only: `Packages/FountainApps/Sources/FountainLauncherUI/AGENTS.md`.
- Composer Studio (fresh app) — new work: `Packages/FountainApps/Sources/composer-studio/AGENTS.md`.

**Maintenance**: This file embeds the unified master plan below. Keep this plan and
`Plans/ROADMAP.md` in sync; prefer editing here and letting `Plans/ROADMAP.md` remain
the canonical “human‑facing” copy for external links.

---

## Unified Master Plan (embedded)

# FountainKit — Unified Product Roadmap (Master Plan)

This is the authoritative plan for FountainKit.

Tracks
- AudioTalk Product (service + orchestration + editors)
- Studio System Introspection & Editing (Control workspace)

Profiles
- Default: Full Fountain stack (gateway, planner, function‑caller, persist,
  bootstrap, baseline‑awareness, tools‑factory, tool‑server, semantic‑browser).
- AudioTalk‑only profile is for focused experiments.

OpenAPI‑first
- Curated, finite spec list (no scans):
  `gateway`, `baseline‑awareness`, `bootstrap`, `planner`, `function‑caller`,
  `persist`, `tools‑factory`, `tool‑server`, `semantic‑browser`, `audiotalk`.
- Edit in UI (Save/Revert) → Lint → Regenerate (swift build) → Reload Routes.

Legacy three‑pane (deprecated)
- Left (Principal): status, repo/build, Start/Stop/Diagnostics, AudioTalk stack,
  inline Environment (Keychain‑backed secrets).
- Middle (Editing): main logs (follow tail), later other editors on demand.
- Right (Optionals): OpenAPI, Routes (viewer + diff), Services tails, Persona,
  Semantic Memory.

Composer‑first story (authoritative for the new app)
- Model: screenplay text (.fountain) with inline tags → parsed model → mapped cue plans → applied notation → journaled timeline (+ UMP batches).
- States: No session → Source stored (ETag) → Parsed → Cued → Applied → Journaled.
- Why: determinism (ETags), reproducibility (journal), separation (idea→structure→actions→artifact), security (Keychain), OpenAPI‑first change control.

Change Now (must converge UI to story)
- Introduce “Screenplay Session” flow as the default storyline:
  - Create/select session; show current ETag.
  - Actions gate by preconditions: Parse → Map Cues → Apply.
  - Results cards after each action: warnings, counts, preview links.
  - Journal timeline: stored/parsed/cued/applied with anchors and timestamps.
- Provide one readiness verdict: Keychain OK + URLs valid + services healthy.
- Keep operator and curator surfaces separate from the composer flow.

AudioTalk Product (essentials)
- Screenplay source (ETag), parse → model (scenes/beats/tags/characters),
  map cues, cue‑sheet JSON/CSV/PDF, UMP persistence, Journal events.
- Apply cues → Lily (ETag‑aware); anchors; `scan-anchors` endpoint; selection sync.
- Planner + FunctionCaller orchestration; ToolsFactory registration.

Studio System Introspection (essentials)
- OpenAPI curated editor; regeneration; gateway reload; routes viewer.
- Persona editor (`Configuration/persona.yaml`) + effective persona preview.
- Semantic memory compute: query Journal/Dictionary/Macros/Anchors and render a
  deterministic snapshot used by the LLM.
- Unified diagnostics: service health, merged logs, tail with filters.

Testing & TDD (applies to all)
- Every feature ships with tests; prefer TDD for logic.
- Unit: spec curation mapping, routes diff, persona round‑trip, memory compute.
- Integration: generator plugins invoked; reload hits gateway; log filters.
- E2E: `Scripts/dev-up --check` → health probes → GET `/admin/routes` assert
  minimal set → `Scripts/dev-down`.
- CI: lint + build + tests gate merges; coverage trend required.

Milestones (high level)
1) M0 Stabilize/Trim: Full stack default; Control unified; curated specs.
2) M1 Context Hub: right‑pane segmented (OpenAPI | Routes | Services | Persona | Memory).
3) M2 OpenAPI Pipeline E2E: lint/generate/build/reload + route diff in UI.
4) M3 Persona/Assistant: editor, effective persona, apply hooks.
5) M4 Semantic Memory: compute snapshot; fixtures + deterministic output.
6) M5 Diagnostics: merged logs, filters, health timeline; repro links.
7) M6 Profiles composer: save/load; app scripts generated; Full default.
8) M7 Perf/Hygiene: precompile, quiet warnings.
9) M8 QA/CI: smoke matrix; headless E2E; coverage.
10) M9 Docs: user guide, API refs, onboarding.
