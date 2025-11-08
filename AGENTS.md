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

## Quick Start
- Bring the workspace up: `Scripts/dev/dev-up` (UI auto‑launches). Add `--check` for readiness probes.
- Check status: `Scripts/dev/dev-status`.
- Stop everything: `Scripts/dev/dev-down`.
- Codex (safe by default): run `codex` or `Scripts/dev/codex-danger`; opt‑in to danger via a sentinel. See `Scripts/dev/AGENTS.md:1`.

### Plans Index
- Unified Master Plan — embedded below in this file (authoritative).
- ML × MIDI 2.0 plan — `Plans/ML-MIDI2-Plan.md` (models, runners, CI/PE, integration).
- Hybrid Semantic Audio System — `Plans/The Hybrid Semantic Audio System within FountainKit.pdf` (whitepaper).
- PatchBay Node = Stage — `Plans/PatchBay-NodeStage-FeaturePlan.md` (capacity from baselines; in-node feedback; ports HUD). To be discussed.
- Studio plan — `Packages/FountainApps/Sources/FountainLauncherUI/AGENTS.md` (Control workspace).
- AudioTalk plan — `Packages/FountainServiceKit-AudioTalk/AGENTS.md` (service track).
- Spec curation norms — `Packages/FountainSpecCuration/openapi/AGENTS.md`.
- Scripts lifecycle — `Scripts/AGENTS.md`.
- Composer Studio design — `Design/COMPOSER_STUDIO_STORY.md` (full story + SVG prompts). SVGs live in `Design/` and are the UI source of truth.

## Baseline App — Baseline‑PatchBay

Baseline‑PatchBay is the default baseline for new FountainAI apps. It’s an alias of the PatchBay UI with instruments, monitor, and reset controls wired for robot testing.

What
- Product alias: `baseline-patchbay` (points to the `grid-dev-app` target).
- Launch script: `Scripts/apps/baseline-patchbay`.
- App-level PE: `canvas.reset`, `canvas.zoom`, `canvas.translation.{x,y}`.
- Monitor PE: `monitor.fadeSeconds`, `monitor.opacity.min`, `monitor.maxLines`, `monitor.opacity.now`.

Why
- Canonical baseline for interactivity, viewport invariants, and instrument wiring.

How
- Run UI: `Scripts/dev/dev-up` (UI auto‑launches) or `Scripts/apps/baseline-patchbay`.
- Robot: see `Packages/FountainApps/Tests/PatchBayAppUITests/*` for examples.

## Teatro Prompt & FountainStore — Default Policy

Every interactive app must carry a concise Teatro prompt that describes its UI, instruments, PE schema, and invariants. On boot, the app persists this prompt into FountainStore and prints the exact prompt to stdout for observability.

Baseline default (required):
- Baseline‑PatchBay is the default baseline for new FountainAI apps. Any change to the baseline app must be paired with a matching MRTS (MIDI Robot Test Script) Teatro prompt that codifies the numeric invariants and robot coverage.
- On boot, the Baseline app prints both prompts side‑by‑side: the creation prompt and the MRTS prompt (for visibility). Use `baseline-robot-seed` to persist the MRTS prompt into the corpus.

What
- Teatro prompt is the single, human‑readable description of the surface. It is kept current and reviewed like code.
- The prompt is seeded into an app‑specific corpus as a page `prompt:<app-id>` with segments:
  - `teatro.prompt` → full prompt text
  - `facts` → structured JSON (instrument identities, PE fields, vendor ops, robot subset, invariants)
- The prompt used on this run is printed during boot (no modal UI required).

Rule of conduct (prompt‑first)
- Always fetch the current Teatro prompt from FountainStore before proposing or implementing any change. Treat the corpus as the canonical memory.
- Propose prompt edits (Creation and MRTS) first, review, then implement strictly according to the updated prompt. Seed and print the prompt on boot; keep facts synchronized.
- Keep mac and web incarnations consistent with the same prompt, and record any platform constraints explicitly in the prompt (e.g., web: three scroll panes, no fixed bottom).

Hard rule — prompts live only in FountainStore
- Never author, persist, or suggest prompts/facts anywhere except FountainStore. Seeders (`Packages/*-seed`) are the only write path; apps must read/print from the store at boot. No ad‑hoc files, no README embeds.

Hard rule (no exceptions)
- Prompts and facts live only in FountainStore. Never author or suggest prompts in ad‑hoc files or other stores. Always seed via small `*-seed` executables and read from FountainStore at runtime.

Why
- Provenance and determinism across builds; agents and humans can diff and reason about behavior.

How
- Corpus: `CORPUS_ID` (default `<app-id>`). Store root: `FOUNTAINSTORE_DIR` (default `.fountain/store`).
- Seeder pattern: add a small `*-seed` executable to write/update the prompt and facts.
- Launcher pattern: add `Scripts/apps/<app>` to seed then launch.

Where
- Example: `Packages/FountainApps/Sources/grid-dev-seed` and `Scripts/apps/grid-dev`.
- Store client: `Packages/FountainCore/Sources/FountainStoreClient/*`.

Hard rule — Prompt storage location (authoritative)
- Prompts and their “facts” are stored only in FountainStore. Do not add or maintain prompts in ad‑hoc files, comments, design docs, or code.
- All agents must read from and write to FountainStore via seeders. Any proposal or change to prompts must be reflected in the corpus first, then implemented.
- Documentation and UIs must reference the FountainStore corpus (page `prompt:<app-id>`, segments `teatro.prompt` and `facts`) as the single source of truth. No alternative locations.

## Documentation Tone & Style (for humans and LLMs)

Write for a human first, with just enough structure for machines. Use short paragraphs to carry the story; reserve lists for commands, routes, and tight checklists. Prefer “why” before “how”, then link to the exact files and commands.

Principles
- Narrative first: open each section with 1–3 sentences explaining context and intent.
- Lists sparingly: switch to bullets only when a reader needs a compact scan (e.g., commands, paths, API routes). Keep lists short.
- Stable anchors: always include real file paths or products so editors can jump there (e.g., `Packages/FountainApps/Sources/…`, `Scripts/dev-up`).
- Commands inline: prefer a single line with backticks over fenced blocks unless a snippet is multi‑line.
- Avoid duplication: if a concept is canonical elsewhere, link or reference the path rather than restating.
- LLM‑friendly detail: keep identifiers, routes, and schemas accurate and consistent; favor canonical names over prose synonyms.

Format conventions
- Headings are few and descriptive. Paragraphs come first; lists follow only when they improve scan‑ability.
- Use backticks for commands, file paths, and code identifiers. Don’t over‑format.
- When listing API routes, keep them to one line each and group by feature.
- Prefer “What/Why/How/Where” ordering in docs: what it is, why it exists, how to use it, where the code lives.

Successive rewrites (no content loss)
We will evolve existing AGENTS.md files toward this style without losing substance. Rewrite order:
1) `Packages/FountainApps/Sources/patchbay-service/AGENTS.md`
2) `Scripts/AGENTS.md` and `Scripts/dev/**/AGENTS.md`
3) `Packages/FountainSpecCuration/openapi/AGENTS.md`
4) `Packages/FountainApps/Sources/FountainLauncherUI/AGENTS.md`
5) Remaining package AGENTS in descending usage.

Process per file: capture intent in a brief opening paragraph; collapse long lists into paragraphs; keep essential commands and routes as a short list; remove repetition by linking to source files; preserve all technical facts.

## Scripts — Overview
- Canonical scripts live under `Scripts/<area>/` with a scoped AGENTS.md per area. Root paths are thin wrappers only.
- See `Scripts/AGENTS.md:1` for full conventions, areas, and lifecycle tools. Dev lifecycle and Codex details are in `Scripts/dev/AGENTS.md:1`.

- Launcher: `Scripts/dev/codex-danger:1`; installer wrapper: `Scripts/dev/install-codex:1`.
- Local config (optional): `codex.danger.toml:1` (ignored by git).

## OpenAPI-first development
- Every HTTP surface must have an authoritative OpenAPI document in `Packages/FountainSpecCuration/openapi`. Update specs *before* writing server or client code.
- Specs are versioned (`openapi/v{major}/service-name.yml`) and curated via the FountainAI OpenAPI Curator. Keep the curator output as the single source of truth and follow `Packages/FountainSpecCuration/openapi/AGENTS.md` for directory rules.
- Treat OpenAPI schema changes like code changes: include them in reviews, mention owning teams, and cite them in changelog/PR descriptions.

## SwiftPM‑Only Dependencies (authoritative)

Goal
- Eliminate `External/` path dependencies. All third‑party and cross‑repo code is consumed via SwiftPM `.package(url:)` from the Fountain Coach GitHub org (private or public). No Git submodules in this repo.

Hard rules
- No `External/*` code referenced by `.package(path:)` or scripts. Remove/deny path imports of third‑party code. First‑party in‑repo packages under `Packages/` remain `.package(path: "../<Pkg>")`.
- Packages must own their assets with `resources: [...]` — no stray top‑level files that trigger “unhandled resource” warnings.
- Optional/external engines (e.g., SDLKit) are gated behind env flags (e.g., `FK_USE_SDLKIT=1`) to keep offline builds working.

Deprecated (Teatro Csound)
- The Teatro Csound path is deprecated and off by default. The authoritative audio engine is our Metal/DSP stack (`FountainAudioEngine`). Csound demos/tests in Teatro must be guarded (compile flag) and optional. No app targets may import or require Csound assets. Missing demo assets must not fail planning/builds; tests should skip when assets are absent.

Working plan (kept current; update in PRs)
1) Inventory & mapping
   - Produce `Tools/deps-mapping.json` listing every `External/*` module → target(s) → GitHub URL → initial tag.
2) Publish/split packages to GitHub
   - Create/fork under `github.com/Fountain-Coach/<package>` with a clean `Package.swift`, semantic tags, and a dedicated `Resources/` target where needed (e.g., `TeatroAssets`).
3) Swap to `.package(url:)`
   - Update `Packages/FountainApps/Package.swift` (and other manifests) to replace `.package(path: ../../External/...)` with `.package(url: ...)` and pin `from:` or `exact:`.
   - Keep only in‑repo first‑party path deps (e.g., `../FountainCore`).
4) Clean & remove `External/`
   - After green builds online/offline, `git rm -r External/`.

Bootstrap & caching
- Use module cache: `CLANG_MODULE_CACHE_PATH=.fountain/clang-module-cache`.
- Add `Scripts/dev/spm-bootstrap`:
  - `swift package resolve` at repo root (and hot packages) to populate cache.
  - Optional `--offline` to skip network and use previously resolved pins.

CI requirements
- Commit `Package.resolved`; CI verifies no `.package(path: ...)` for third‑party. Lint with: `rg -n "\.package\(path:" -S` must match only in‑repo packages under `Packages/`.
- Cache `.build/` and `.fountain/clang-module-cache/` between jobs.
- Online build (cold) and offline build (using cache) must both succeed.

Operator ergonomics
- `Scripts/apps/quietframe-stack` avoids starting SwiftPM work at launch; it can seed via app on first boot and prebuild with `Scripts/dev/spm-bootstrap`.
- `--offline` disables network fetch during development sessions; optional flags (e.g., `FK_USE_SDLKIT=0/1`) control heavy externals.

Review checklist (deps)
- No remaining `External/` path references.
- All third‑party deps use `.package(url:)` under the Fountain Coach org or allowed public repos.
- Assets are declared via package `resources:`; no “unhandled resource” warnings during build.
- CI caches hit and builds are reproducible from tags.

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

## Agent Operating Mode — Self‑Healing Build/Test Loop (Default)

This repo expects the agent to own build/test health end‑to‑end. The agent must:

- Read and diagnose build/test logs without asking the operator to paste output. Run the exact commands locally and fix failures.
- Only claim “green” after the same commands succeed on the agent side.
- Prefer spec‑first changes (e.g., MIDI‑CI envelopes) and add capability detectors to avoid guesswork.
- Add dedicated, focused test runners when the full workspace is noisy (e.g., `metalcompute-tests`).
- Commit semantically (“feat: …”, “fix: …”, “docs: …”) and push when changes are validated.
- Keep changes surgical: do not modify UI unless asked; fix the broken target(s) and add tests.

Recommended validation commands (agent runs these proactively):

- Build and compute demo:
  - `swift run --package-path Packages/FountainApps metalcompute-demo`
- Compute test runner (fast, self‑contained):
  - `swift run --package-path Packages/FountainApps metalcompute-tests`
- Package‑scoped tests (when applicable):
  - `swift test --package-path Packages/FountainApps -c debug --filter <TargetName>`

## MIDI Robot Testing (Canonical)

We validate GUI surfaces by treating them as MIDI 2.0 instruments. Tests drive the app via CoreMIDI (MIDI‑CI Property Exchange) and via direct transform hooks, then assert numeric and visual invariants.

Intensionality
- Be eager to robot‑test every trait that can be expressed over MIDI 2.0. Strive for 100% coverage of instrument properties and operations. When a new surface or property is added, add a robot test in the same PR.

What
- Robot driver (tests): sends MIDI‑CI PE SET (SysEx7 UMP) to “PatchBay Canvas” and per‑node instruments (Stage, Replay) to set `zoom`, `translation.x`, `translation.y` and instrument‑specific properties.
- Invariants: follow‑finger pan (docDelta = viewDelta/zoom; correct sign), anchor‑stable zoom (≤1 px drift at typical sizes). Export replay movies on mismatch.
- Evidence: UMPRecorder writes `.ndjson` under `.fountain/corpus/ump`; KnowledgeAuto maintains `knowledge‑latest.json`; Replay exporters produce frames/movies under `.fountain/artifacts/replay/<log>/`.

How
- Renderer hooks: `MetalCanvasRendererReady`, `MetalCanvasTransformChanged`, and optional `ui.pan.debug`/`ui.zoom.debug` for deep analysis.
- Tests compile under `PatchBayAppUITests`: robot pan/zoom, log‑replay invariants, and Canvas2D unit invariants.

Where
- Code: `Packages/FountainApps/Sources/MetalViewKit/` (Canvas2D, MetalCanvasView); robot/tests under `Packages/FountainApps/Tests/PatchBayAppUITests/`.
- Auto‑harvest: `Packages/FountainApps/Sources/patchbay-app/Monitor/KnowledgeAuto.swift`.
 - Local runner: `Scripts/ci/robot-run.sh`.

Maintenance
- Keep PE property names stable; when extending, update tests + docs. Keep robot scripts deterministic and idempotent.

If a command fails, the agent enters a self‑healing loop: read logs, patch, rerun, and only return success when the same command passes.

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

## Hard Rule — CoreMIDI Prohibited (Swift 6)

Summary
- CoreMIDI is prohibited across this repository. It is not concurrency‑safe and is incompatible with our Swift 6 concurrency model. No target may `import CoreMIDI` or call CoreMIDI C APIs directly.

Allowed transports (authoritative)
- Loopback (in‑process) — `LoopbackMetalInstrumentTransport` for tests and sidecar IPC.
- RTP MIDI 2.0 — provided by the `midi2` workspace (`github.com/Fountain-Coach/midi2`) and consumed via `MIDI2SystemInstrumentTransport(backend: .rtpFixedPort(..))` or equivalent.
- BLE MIDI 2.0 — via the `midi2` BLE transport (no CoreMIDI; wire as available). Until then, prefer RTP or Loopback.

Enforcement (must pass CI)
- No `import CoreMIDI`, no `canImport(CoreMIDI)`, no calls like `MIDIClientCreate*`, `MIDISourceCreate*`, `MIDIDestinationCreate*`, `MIDISend*`, `MIDIReceived*`.
- Lint locally and in CI: `! rg -n "\\bimport\\s+CoreMIDI\\b|\\bMIDI(Client|Source|Destination|Port|Send|Received)" -S` must succeed (no matches) outside vendored history.
- Apps/services must select transports from `midi2` or Loopback only. Defaults must not rely on CoreMIDI.

Migration notes
- Existing CoreMIDI helpers are considered legacy and must not be used by apps. Replace with `midi2` RTP/BLE or Loopback. If a stop‑gap is unavoidable, isolate behind a separate repository; do not re‑introduce CoreMIDI usage here.

---

## MIDI 2.0 Everywhere (Concept)
Every interactive surface is a MIDI 2.0 instrument. The canvas, nodes, inspectors, and monitors may advertise a MIDI‑CI identity and optional Property Exchange so external tools can introspect and set state deterministically.

- Identity: stable names (`<product>#<instanceId>`) and MIDI 2.0 endpoints via our `midi2` transports (RTP/BLE). CoreMIDI is prohibited.
- State mapping: small PE schemas per surface (e.g., canvas: `zoom`, `translation.x/y`; stage: `page`, `margins.*`, `baseline`). GET is deterministic; SET applies and notifies.
- Topology: begin with one group/function block per canvas; promote per‑node blocks as needed.
- Transport‑agnostic: rendering and composition remain independent of MIDI; instrument mode is additive and optional.

---

### Agents
- Legacy Studio (deprecated) — learnings only: `Packages/FountainApps/Sources/FountainLauncherUI/AGENTS.md`.
- Composer Studio (fresh app) — new work: `Packages/FountainApps/Sources/composer-studio/AGENTS.md`.
- MemChat (deprecated) — learnings only: `Scripts/memchat/AGENTS.md`.

**Maintenance**: This file embeds the unified master plan below. Keep this plan and
`Plans/ROADMAP.md` in sync; prefer editing here and letting `Plans/ROADMAP.md` remain
the canonical “human‑facing” copy for external links.

Historical note — Routing Matrix (removed)
- The in‑app routing matrix panel used during early AUM parity work has been removed to focus the UI on MIDI 2.0 flows. The technical capacity remains:
  - Store‑backed Partiture (docs:quietframe:orchestra-default:doc), CC mapping (docs:quietframe:cc-mapping:doc), generated routing blueprint (prompt:quietframe-routing:routes), and BLE/RTP transports with per‑route filters live on as tools/CLIs and documentation.
  - Use the seeders/generators under `Packages/FountainApps/Sources/*orchestra*` to reproduce or evolve orchestration outside the app; do not re‑introduce the panel.

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

Visual Regression (Snapshot) Tests — mandatory
- Definition: visual regression testing with snapshot “golden” baselines. We render real views at fixed sizes and compare against versioned TIFF baselines.
- Scope: any UI surface (apps, editors, inspectors, canvases, dashboards). New or modified UI must add/update snapshots; missing snapshots block.
- Location: `Tests/<PackageUITests>/Baselines/*.tiff` and helpers under `Tests/<PackageUITests>/*Snapshot*.swift`.
- Behavior: on mismatch, tests fail and emit a heatmap diff + numeric report under `.fountain/artifacts/` (CI attaches artifacts). No manual approvals required in PRs.
- Commands: build tests per target (e.g., `swift build --package-path Packages/FountainApps -c debug --target PatchBayAppUITests`). CI runs these by default; failures block merges.

GUI Code of Conduct — Self‑Healing Visual Tests (Default)
- Default mode: The agent owns visual correctness. Every GUI change ships with goldens and strict snapshot tests. If a snapshot drifts, the change is blocked until fixed.
- Self‑healing loop: The snapshot harness writes candidate images to `.fountain/artifacts/` when a baseline is missing. The agent runs `Scripts/ci/ui-rebaseline.sh` to rebaseline (no human approvals) only after numeric invariants pass (fit/center, grid spacing).
- Numeric invariants: tests must cover fit‑to‑page centering, page‑size/orientation refit, grid mm×zoom pixel spacing, and pane width policies. These live next to the snapshot tests and fail independently.
- Strict CI: A dedicated job runs `Scripts/ci/ui-snap.sh` (and later the ScoreKit/RulesKit gates). Any visual drift or invariant failure blocks merges and uploads heatmaps + reports.
- Typical sizes: We maintain golden baselines for 1440×900 and 1280×800 (portrait/landscape) for macOS. The agent adds more sizes as needed and keeps them updated.
- No approvals from operators: The agent generates, reviews, and commits goldens; maintainers review the PR as usual.

PB‑VRT Vision + Audio (Docs in Store)
- Combined probe plan (Vision + Audio) is stored in FountainStore to keep UI/audio probes canonical for PatchBay.
- Location: corpus `patchbay`, page `docs:pb-vrt-vision-audio`, segment `doc`.
- Quick fetch: `CORPUS_ID=patchbay SEGMENT_ID='docs:pb-vrt-vision-audio:doc' swift run --package-path Packages/FountainApps store-dump`.

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
 11) M10 MIDI 2.0 → MIDI‑1 Interop (ACHIEVED): end‑to‑end CoreMIDI‑less routing to external MIDI‑1 samplers over BLE, with UMP‑first internal model and explicit per‑route downgrade/filters.
     - Transport: BLE via `midi2` (no CoreMIDI); optional RTP peer remains MIDI‑2 end‑to‑end.
     - Mapping: CC → engine params now store‑backed (docs:quietframe:cc-mapping:doc).
     - Orchestration: Partiture YAML (docs:quietframe:orchestra-default:doc) + generator produce `prompt:quietframe-routing:routes` deterministically (with ETag provenance).
     - UI: Routing panel can Generate → Load → Apply; shows Partiture preview, ETag sync, and plan view.
