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

## Core Contract (read first)

- Prompts + facts: Teatro prompts and PE facts live only in FountainStore, never in ad‑hoc files. Apps must seed via small `*-seed` executables and read/print prompts from the store on boot.
- Baseline: `baseline-patchbay` (grid‑dev‑app) is the canonical UI baseline for viewport math and robot invariants. Any change to the baseline must ship a matching MRTS Teatro prompt and keep robot tests green.
- Engines: CoreMIDI and UIKit are banned; new interactive work (Infinity and successors) must use SDLKit for windowing/events and our own canvas core (`Canvas2D` + node/edge graph). AppKit/SwiftUI remain only for legacy surfaces.
- Infinity: the “Infinity” app is the forward workbench surface — an SDLKit‑backed, instant‑start, offline‑capable canvas that runs directly on our graph; no servers or control‑plane boot are required to sketch.
- OpenAPI‑first: every HTTP surface and instrument capability surface is defined by curated OpenAPI under `Packages/FountainSpecCuration/openapi`; server/client types and PE facts are always generated from these specs.
- Store + secrets: FountainStore is the only authority for prompts, facts, graphs, and secrets. Secrets must be seeded via store tools, not environment variables.
- Dependencies: third‑party code comes via SwiftPM `.package(url:)` from the Fountain Coach org; `External/` path imports are being removed and must not be reintroduced.
- Build/test discipline: changes must compile with `swift build` at the root and pass focused `swift test --package-path Packages/<Package>` on touched packages before they are considered “green”.
- 3D hard rule: across FountainAI, the only allowed 3D stack is `three.js` + `cannon.js`. Do not add or extend any other 3D/WebGL/WebGPU/Metal/D3D/Vulkan frameworks; existing non‑Three/Cannon 3D paths are frozen and must be removed or replaced with the Three + Cannon pair.
- Native 3D gating: SwiftPM manifest now drops Metal/SDL native 3D products/targets by default. Set `FK_ALLOW_NATIVE_3D=1` only if temporarily needed while migrating; otherwise native 3D code is out of the build.

## Quick Start
- Bring the workspace up: `Scripts/dev/dev-up` (UI auto‑launches). Add `--check` for readiness probes.
- Check status: `Scripts/dev/dev-status`.
- Stop everything: `Scripts/dev/dev-down`.
- Codex (safe by default): run `codex` or `Scripts/dev/codex-danger`; opt‑in to danger via a sentinel. See `Scripts/dev/AGENTS.md:1`.

### Plans Index
- Unified Master Plan — embedded below in this file (authoritative).
- ML × MIDI 2.0 plan — `Plans/ML-MIDI2-Plan.md` (models, runners, CI/PE, integration).
- PatchBay Node = Stage — `Plans/PatchBay-NodeStage-FeaturePlan.md` (capacity from baselines; in-node feedback; ports HUD). To be discussed.
- Infinity workbench — `Plans/Infinity-Plan.md` (SDLKit infinite canvas instrument; keep this plan current as Infinity evolves).
- Instrument requirements — `Design/INSTRUMENT_REQUIREMENTS.md` (what every instrument must provide: prompt, spec, facts, MIDI host wiring, tests).
- FountainGUIKit demo integration — `Plans/FountainGUIKit-Demo-Plan.md` (NSView host, gestures, MIDI 2.0, MRTS/PB‑VRT).
- MetalViewKit runtime instrument state — `Plans/MetalViewKitRuntime-InstrumentStatePlan.md` (generic instrument state API, facts integration, MIDI host wiring).
- Instrument template and generator — `Plans/instrument-new-plan.md` (canonical `instrument-new` template and workflow).
- Hybrid Semantic Audio System — `Plans/Legacy/The Hybrid Semantic Audio System within FountainKit.pdf` (whitepaper; legacy background).
- Studio plan — `Packages/FountainApps/Sources/FountainLauncherUI/AGENTS.md` (Control workspace).
- AudioTalk plan — `Packages/FountainServiceKit-AudioTalk/AGENTS.md` (service track).
- Spec curation norms — `Packages/FountainSpecCuration/openapi/AGENTS.md`.
- Scripts lifecycle — `Scripts/AGENTS.md`.
- Composer Studio design — `Design/COMPOSER_STUDIO_STORY.md` (full story + SVG prompts). SVGs live in `Design/` and are the UI source of truth.
 - Teatro Stage instruments map — `Design/TeatroStage-Instruments-Map.md` (how the Teatro Stage Engine maps into FountainKit instruments and hosts).

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
- One‑click MPE demo: `Scripts/apps/mpe-pad-app` (launches the Baseline app; enable BLE and Open in the left‑pane MPE Pad, set filter to “AUM”).
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

- Targeted wrappers index: fast single‑service builds/runs are documented under `Scripts/AGENTS.md` (section “Targeted Wrappers (Service‑Minimal)”). Use `Scripts/dev/<service>-min [build|run]` to compile only that server.

- Launcher: `Scripts/dev/codex-danger:1`; installer wrapper: `Scripts/dev/install-codex:1`.
- Local config (optional): `codex.danger.toml:1` (ignored by git).

### Service‑Minimal — Targeted Builds (Authoritative Pattern)

What
- Keep the manifest stable; avoid monorepo‑wide gating. Build exactly one service with a small transitive graph.
- Move OpenAPI generation into a `<service>-service` library target (core). The server executable depends on this core and never declares the generator plug‑in.
- Filter the generator via `openapi-generator-config.yaml` to only emit that service’s routes.
- Thin servers only wire transports and register generated handlers; no smoke or test codepaths in mains.

Why
- Faster compiles (generator runs once per service in a library; executables are thin) and fewer cache invalidations.
- Non‑destructive: OpenAPI remains curated under `Packages/FountainSpecCuration/openapi`, manifests stay stable, and other services are unaffected.
- Deterministic: per‑service wrappers ensure targeted builds without pulling the whole workspace.

How
- Core example: `Packages/FountainApps/Sources/fountain-editor-service` (owns `openapi.yaml` symlink + generator config; exports API protocol).
- Server example: `Packages/FountainApps/Sources/fountain-editor-service-server` (depends on core + FountainRuntime; no plugin/spec).
- Build one: `swift build --package-path Packages/FountainApps -c debug --target <service>-service-server`.
- Wrappers: `Scripts/dev/*-min` export `FK_SKIP_NOISY_TARGETS=1` and a service selector (e.g., `FK_EDITOR_MINIMAL=1`). No `smoke` for any server.

Wrappers Index
- editor: `Scripts/dev/editor-min` (build|run)
- gateway: `Scripts/dev/gateway-min` (build|run)
- pbvrt: `Scripts/dev/pbvrt-min` (build|run)
- quietframe: `Scripts/dev/quietframe-min` (build|run)
- planner: `Scripts/dev/planner-min` (build|run)
- function-caller: `Scripts/dev/function-caller-min` (build|run)
- persist: `Scripts/dev/persist-min` (build|run)
- baseline-awareness: `Scripts/dev/baseline-awareness-min` (build|run)
- bootstrap: `Scripts/dev/bootstrap-min` (build|run)
- tools-factory: `Scripts/dev/tools-factory-min` (build|run)
- tool-server: `Scripts/dev/tool-server-min` (build|run)

Persistence (Teatro prompt)
- The pattern is seeded into FountainStore under corpus `service-minimal` via `Scripts/apps/service-minimal-seed`.
- Segments: `prompt:service-minimal:teatro` (prompt) and `prompt:service-minimal:facts` (JSON facts). Apps/scripts must read these at runtime; no ad‑hoc copies.


## Targeted Builds — Editor‑Minimal Pattern
We optimize compile time by gating the package manifest and deduplicating OpenAPI generation. The editor server compiles in isolation with a tiny dependency graph and a single generator pass.

What
- Editor‑minimal mode builds only `fountain-editor-service-core` and `fountain-editor-service-server`.
- OpenAPI generator runs in the core target; the server target has no plugin and no duplicate `openapi.*`.
- Generator is filtered to editor routes only.

Why
- Dramatically reduces cold build time and churn from unrelated targets.
- Keeps iteration focused on the editor service (ETag flow, placements, structure).

How
- Use the helper: `Scripts/dev/editor-min [build|run|smoke]`.
- Env gates (set automatically by the helper):
  - `FK_EDITOR_MINIMAL=1` and `FK_SKIP_NOISY_TARGETS=1` → minimal products/deps/targets in `Packages/FountainApps/Package.swift`.
  - `FOUNTAIN_SKIP_LAUNCHER_SIG=1` → skip launcher signature during local dev.
- Single‑source OpenAPI:
  - Spec: `Packages/FountainApps/Sources/fountain-editor-service/openapi.yaml`.
  - Config: `Packages/FountainApps/Sources/fountain-editor-service/openapi-generator-config.yaml` (with `filter.paths` for editor routes).
  - Core owns `OpenAPIGenerator` plugin; server does not.

Commands
- Minimal build: `Scripts/dev/editor-min build`
- Run server: `Scripts/dev/editor-min run`
- In‑process smoke (no network): `Scripts/dev/editor-min smoke`

Persistence (Teatro prompt)
- The canonical build‑pattern prompt is persisted in FountainStore — do not copy into files.
- Corpus: `build-profiles`; Page: `prompt:service-minimal`.
- Seeder: `Scripts/apps/service-minimal-seed` (writes `teatro.prompt` and `facts`).
- Quick fetch:
  - `CORPUS_ID=build-profiles SEGMENT_ID='prompt:service-minimal:teatro' swift run --package-path Packages/FountainApps store-dump`
  - `CORPUS_ID=build-profiles SEGMENT_ID='prompt:service-minimal:facts' swift run --package-path Packages/FountainApps store-dump`

Where
- Manifest gating and targets live in `Packages/FountainApps/Package.swift:1`.
- Editor server sources: `Packages/FountainApps/Sources/fountain-editor-service-server/*`.
- Core + handlers/types: `Packages/FountainApps/Sources/fountain-editor-service/*`.

## OpenAPI-first development
- Every HTTP surface must have an authoritative OpenAPI document in `Packages/FountainSpecCuration/openapi`. Update specs *before* writing server or client code.
- Specs are versioned (`openapi/v{major}/service-name.yml`) and curated via the FountainAI OpenAPI Curator. Keep the curator output as the single source of truth and follow `Packages/FountainSpecCuration/openapi/AGENTS.md` for directory rules.
- Treat OpenAPI schema changes like code changes: include them in reviews, mention owning teams, and cite them in changelog/PR descriptions.

## OpenAPI → PE Facts (Authoritative)

What
- Capability surfaces for instruments are derived from curated OpenAPI specs. A generator produces Property Exchange “facts” that map each operation to a PE property, and the instrument host executes mapped operations automatically.

Why
- Spec‑driven and deterministic: the same OpenAPI that drives HTTP types also defines the instrument’s PE surface. No ad‑hoc YAML; facts are generated and stored centrally.

How
- Per‑agent seeding (authoritative for dev/interactive): build the tooling once and call `openapi-to-facts` for exactly one spec/agent.
  - Build: `swift build --package-path Packages/FountainTooling -c debug --target openapi-to-facts`.
  - Seed one: `FOUNTAINSTORE_DIR=.fountain/store swift run --package-path Packages/FountainTooling -c debug openapi-to-facts Packages/FountainSpecCuration/openapi/v1/<spec>.yml --agent-id fountain.coach/agent/<name>/service --seed --allow-tools-only`.
  - Mapping file (authoritative): `Tools/openapi-facts-mapping.json` lists `{ spec, agentId }` pairs for all agents.
  - Store: `agent-facts` collection at id `facts:agent:<agentId>` (`/` replaced by `|`).
- The legacy batch script `Scripts/openapi/openapi-to-facts.sh` is intentionally **disabled**; do not use it in CI or dev flows.
- Runtime seeding via Tools Factory (recommended for interactive authoring): POST a spec to Tools Factory and receive seeded facts immediately.
  - Endpoint: `POST /agent-facts/from-openapi` on `tools-factory-server`.
  - Body (JSON): `{ "agentId": "fountain.coach/agent/<name>/service", "corpusId": "agents", "seed": true, "openapi": {…} }` or `{ "specURL": "http://<service>/openapi.yaml" }`.
  - Response: facts JSON (also written into FountainStore when `seed: true`).
  - Start server: `Scripts/dev/tools-factory-min run` (port `:8011`).
- Secrets seeding via Tools Factory: upsert headers for an agent.
  - Endpoint: `POST /agent-secrets` on `tools-factory-server`.
  - Body (JSON): `{ "agentId": "fountain.coach/agent/<name>/service", "corpusId": "secrets", "headers": { "Authorization": "Bearer …", "X-API-Key": "…" } }`.
  - Result: `{ ok: true, id, corpus }` on success.
- Serve facts: Gateway exposes `/.well-known/agent-facts` (Store‑backed)
- Host: the MIDI Instrument Host loads facts, advertises CI/PE, and routes PE SET/GET to mapped OpenAPI ops.

Secrets (SecretStore + FountainStore, no env policy)
- Primary secret backend for human‑entered credentials is `SecretStore` (Keychain on macOS, libsecret on Linux), accessed via `SecretStoreHelper` (see `Packages/FountainApps/Sources/EngraverChatCore/SecretStoreHelper.swift`).
- FountainStore is used to hold **per‑agent header maps** (ready‑to‑send HTTP headers), not raw API keys; these are typically derived from SecretStore or seeded once, then read by hosts/tools.
- Do not pass credentials via environment in steady‑state; env overrides are only for migration or bootstrapping, not the main path.
- FountainStore secrets corpus:
  - Corpus: `secrets` (default, override with `SECRETS_CORPUS_ID` when needed).
  - Collection: `secrets`.
  - Document ids (in priority order):
    - `secret:agent:<agent-id>` with `/` replaced by `|` (e.g., `secret:agent:fountain.coach|agent|tools-factory|service`).
    - `secret:agent:<agent-id>` (raw).
    - `secret:default` (fallback).
  - Document body: `{ "headers": { "Authorization": "Bearer …", "X-API-Key": "…" } }` or a flat header map.
- Seeders:
  - CLI: `swift run --package-path Packages/FountainApps secrets-seed --agent-id <id> --header Authorization="Bearer sk-..." [--header X-API-Key=...]`.
  - Tools Factory: `POST /agent-secrets` on `tools-factory-server` with `{ agentId, corpusId?: "secrets", headers: { ... } }` (behind `TOOLS_FACTORY_ALLOW_SECRET_UPSERT=1` and optional admin key).
  - Convenience wrapper: `Scripts/apps/secrets-seed` (same flags as above) to write header maps without touching env.

Where
- Generator: `Packages/FountainTooling/Sources/openapi-to-facts`
- Tools Factory runtime endpoint: `Packages/FountainApps/Sources/tools-factory-server/main.swift:1` (`/agent-facts/from-openapi`, `/agent-facts`).
- Gateway facts endpoint: `Packages/FountainApps/Sources/gateway-server/GatewayServer.swift:1`
- Host (prototype): `Packages/FountainApps/Sources/midi-instrument-host`

Rules
- Facts live only in FountainStore; never in ad‑hoc files. Specs are the source of truth; facts are generated from specs.
- For new services, add the spec under `Packages/FountainSpecCuration/openapi/v1/<service>.yml`, then extend `Tools/openapi-facts-mapping.json` with the `{spec, agentId}` mapping and generate facts per‑agent via `openapi-to-facts` or Tools Factory.

## Instrument Creation Pipeline — Prompt + Facts (Authoritative)

Every first‑class instrument follows a contract‑first pipeline: spec, prompt, facts, tests.

What
- Prompts are generated, not free‑handed: authors describe the surface and tests in a structured contract, and a factory renders both the Teatro prompt and its facts.
- Facts come from curated OpenAPI and are stored centrally; runtime components (Tools Factory, Gateway, MIDI hosts, LLM tools) read facts instead of re‑parsing specs.

How
- Prompt contract:
  - Author a `TeatroPromptContract` (scene title, host/surface, cores, properties, invariants, tests) for each new instrument/app.
  - Spec: `Packages/FountainSpecCuration/openapi/v1/teatro-prompt-factory.yml` defines the contract schema and response bundle.
- Prompt factory:
  - Factory CLI: `swift run --package-path Packages/FountainTooling -c debug teatro-prompt-factory --input <contract.json>` produces `{ promptText, facts }`.
  - Seed into FountainStore via a small `*-seed` executable: write `prompt:<appId>:teatro` and `prompt:<appId>:facts` segments; apps read and print the prompt on boot.
- Facts factory:
  - OpenAPI spec lives under `Packages/FountainSpecCuration/openapi/v1/<service>.yml` and is mapped in `Tools/openapi-facts-mapping.json` to an `agentId`.
  - Generate facts per agent with either:
    - CLI: `openapi-to-facts` (per‑agent, as described above), or
    - Tools Factory: `POST /agent-facts/from-openapi` (`Packages/FountainApps/Sources/tools-factory-server/main.swift:1`) with `{agentId, corpusId, seed, openapi/specURL}`.
  - Facts are served via Gateway (`/.well-known/agent-facts`) and consumed by hosts (`midi-instrument-host`, LLM tools).
- Tests linkage:
  - Facts and prompts must name the owning test module and suites (see `Design/INSTRUMENT_REQUIREMENTS.md`); `Tools/instruments.json` and `instrument-lint` enforce the presence of tests and symbols.

Rules
- No hand‑written prompts in code or docs: always go through the Teatro prompt factory and seeders.
- No batch regeneration of all facts: use per‑agent generation or Tools Factory; the legacy script under `Scripts/openapi/openapi-to-facts.sh` is disabled and must not be re‑enabled.

## FountainStore Schema & Seeders (Authoritative)

FountainStore is the single backing store for prompts, facts, instruments, and secrets. Instead of generic “PUT any JSON anywhere”, we keep a small, named set of corpora and collections, each owned by a seeder or factory.

What
- Per‑app corpora (`<app-id>`):
  - Corpus: `<app-id>` (e.g., `grid-dev`, `baseline-patchbay`, `infinity`).
  - Collection: `segments`.
  - Documents:
    - `prompt:<app-id>:teatro` → Teatro creation prompt (text).
    - `prompt:<app-id>:facts` → companion JSON facts for that surface.
    - Other app‑specific segments as needed (e.g., docs, baselines) with the same `segments` pattern.
  - Seeders:
    - Small `*-seed` executables under `Packages/FountainApps/Sources/*-seed` (for example `grid-dev-seed`, `baseline-robot-seed`, `infinity-seed`).
    - Launchers under `Scripts/apps/<app-id>` call the seeder first, then start the app.

- Agents corpus (`agents`):
  - Corpus: `agents`.
  - Collection: `agent-facts`.
  - Documents:
    - `facts:agent:<agent-id>` with `/` replaced by `|` (for example `facts:agent:fountain.coach|agent|svg-animation|service`).
  - Seeders / factories:
    - CLI: `openapi-to-facts` in `Packages/FountainTooling/Sources/openapi-to-facts` (per‑agent generation with `--seed`).
    - Tools Factory HTTP: `POST /agent-facts/from-openapi` on `tools-factory-server` (`Packages/FountainApps/Sources/tools-factory-server`).
    - Facts‑Factory MIDI instrument exposed by `agent-host` (see `Packages/FountainApps/Sources/midi-instrument-host` and `AGENTS.md` Facts‑Factory section).

- Instruments corpus (`instruments`):
  - Corpus: `instruments`.
  - Collection: `instrument-catalog`.
  - Documents:
    - `instrument:<id>` → one instrument entry (id, title, summary, group, agentIds, version, pricing, enabled).
    - `instrument-catalog:index` → `{ "ids": ["id1","id2",…] }` for fast listing.
  - Seeders / factories:
    - HTTP server: `instrument-catalog-server` (`Packages/FountainApps/Sources/instrument-catalog-server`), `POST /catalog/instrument`.
    - CLI seeder: `instrument-catalog-seed` (`Packages/FountainTooling/Sources/instrument-catalog-seed`) for direct, scriptable catalog updates without starting a server.

- Secrets corpus (`secrets`):
  - Corpus: `secrets`.
  - Collection: `secrets`.
  - Documents (in priority order):
    - `secret:agent:<agent-id>` with `/` replaced by `|`.
    - `secret:agent:<agent-id>` (raw form).
    - `secret:default` as a fallback.
  - Body: `{ "headers": { "Authorization": "Bearer …", "X-API-Key": "…" } }` or a flat header map.
  - Seeders:
    - CLI: `secrets-seed` (`Packages/FountainApps/Sources/secrets-seed`) to materialise per‑agent header maps into FountainStore from an operator‑supplied source (often SecretStore during setup).
    - Wrapper: `Scripts/apps/secrets-seed` with `--agent-id` and repeated `--header` flags.
  - Consumers:
    - MIDI Instrument Host (`midi-instrument-host`) via `loadSecrets` (pulls `secrets` corpus into runtime header maps).
    - Tools Factory when calling external agents on behalf of hosts.

- Other named corpora:
  - Build profiles: `build-profiles` corpus (for example `prompt:service-minimal` segments) seeded by `service-minimal-seed`.
  - Service and demo corpora (for example `audiotalk`, `composer-studio`, `teatro-guide`): each has its own `*-seed` executable and follows the same `segments` pattern for prompts and facts.

How
- Always resolve the store root via `FOUNTAINSTORE_DIR` (default `.fountain/store`), then select a corpus by id.
- Use `FountainStoreClient` from `FountainCore` in seeders and services; do not talk to the underlying on‑disk layout directly.
- For instrument creation, the pipeline is:
  - OpenAPI spec → `openapi-to-facts` / Tools Factory → `agents` corpus (`agent-facts`).
  - Prompt contract → `teatro-prompt-factory` → per‑app corpus (`segments`).
  - Instrument metadata → `instrument-catalog-seed` or `instrument-catalog-server` → `instruments` corpus.
  - Secrets → `secrets-seed` → `secrets` corpus.

Rules
- No raw, ad‑hoc writes into FountainStore: always go through a dedicated seeder or factory that owns the schema for its corpus and collection.
- Keep corpora small and purpose‑specific; new data shapes require either extending an existing corpus/collection schema or introducing a new, documented corpus with a corresponding seeder.
- Treat `Tools/instruments.json` + `instrument-lint` as the gatekeeper for “first‑class” instruments: entries there must have matching specs, prompts, facts, tests, and (when applicable) catalog/agent facts seeded via the tools above.

## SwiftPM‑Only Dependencies (authoritative)

Goal
- Eliminate `External/` path dependencies. All third‑party and cross‑repo code is consumed via SwiftPM `.package(url:)` from the Fountain Coach GitHub org (private or public). No Git submodules in this repo.

Hard rules
- No `External/*` code referenced by `.package(path:)` or scripts. Remove/deny path imports of third‑party code. First‑party in‑repo packages under `Packages/` remain `.package(path: "../<Pkg>")`.
- Packages must own their assets with `resources: [...]` — no stray top‑level files that trigger “unhandled resource” warnings.
- Optional/external engines (e.g., SDLKit) are gated behind env flags (e.g., `FK_USE_SDLKIT=1`) to keep offline builds working.

## Infinity & SDLKit — New Work Contract

For new interactive work (Infinity and follow‑on instruments), we standardise on SDLKit + our own graph/renderer and keep legacy frameworks at the edges only.

What
- GUI host: SDLKit windowing (`SDLWindow`) and renderer (`SDLRenderer`) provide the only interactive surface for new apps like Infinity; SwiftUI and UIKit are prohibited, and AppKit is allowed only inside SDL’s internals or thin legacy shims.
- Canvas core: `Canvas2D` (doc↔view transform) and a small node/edge model form the canonical “infinite canvas” runtime; renderers (MetalViewKit, SDLKit) consume this math without redefining pan/zoom behaviour.
- Infinity app: a new SDLKit‑backed executable (Infinity) uses `Canvas2D` + the graph only, runs without servers by default, and starts from a prebuilt binary so launch feels like a normal desktop app.

Why
- Cross‑platform: SDLKit gives us a portable window/event loop without binding new work to macOS‑only APIs.
- Deterministic math: one transform (`Canvas2D`) keeps pan/zoom behaviour and robot invariants identical across hosts.
- Reduced legacy drag: existing AppKit/SwiftUI apps remain supported but are treated as legacy; Infinity is the forward path for canvas‑centric instruments.

Rules (new work)
- CoreMIDI and UIKit are banned for all targets; no new code may `import CoreMIDI` or `import UIKit`.
- New interactive UIs (Infinity, future canvases, instrument workbenches) must:
  - host windows and events via SDLKit (no SwiftUI views, no direct NSView/NSWindow in their code paths),
  - use `Canvas2D` as the single source of truth for zoom/translation (no ad‑hoc pan/zoom math),
  - keep network/services optional so Infinity can launch instantly in an offline, local‑only mode.
- Legacy AppKit/SwiftUI surfaces remain until migrated but must not be extended for Infinity‑class work; prefer building new tools on the SDLKit/Canvas2D stack instead.

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

## Targeted Builds — Service‑Minimal Pattern (No Manifest Gating)

Context
- Compile times for servers grew beyond acceptable budgets when building the full workspace. We standardize on per‑service, targeted builds without changing the global manifest shape.

Pattern (per service)
- Core owns generation: move `OpenAPIGenerator` plugin and the `openapi.yaml` symlink into `<service>-service` (a library target). Configure `openapi-generator-config.yaml` to `filter.paths` for that service.
- Thin server: `<service>-service-server` depends on the core + `FountainRuntime` and `LauncherSignature`. Do not declare the generator plugin in the executable.
- Targeted build/run: use `swift build --package-path Packages/FountainApps -c debug --target <service>-service-server` and `FOUNTAIN_SKIP_LAUNCHER_SIG=1 swift run --package-path Packages/FountainApps <service>-service-server`.
- No smoke in main: servers start real HTTP only; smoke/e2e lives in scripts/tests.

Adoption status
- Adopted: `fountain-editor`, `gateway-server`, `pbvrt-server`, `quietframe-service-server`.
  - Editor core: `Packages/FountainApps/Sources/fountain-editor-service`, server: `Packages/FountainApps/Sources/fountain-editor-service-server`.
  - Gateway core: `Packages/FountainApps/Sources/gateway-service`, server: `Packages/FountainApps/Sources/gateway-server`.
  - PB‑VRT core: `Packages/FountainApps/Sources/pbvrt-service`, server: `Packages/FountainApps/Sources/pbvrt-server`.
  - QuietFrame core: `Packages/FountainApps/Sources/quietframe-service`, server: `Packages/FountainApps/Sources/quietframe-service-server`.
- Already compliant via ServiceKit cores: `planner-server`, `function-caller-server`, `persist-server`, `baseline-awareness-server`, `bootstrap-server`, `tools-factory-server`, `tool-server` (their OpenAPI generation lives in `Packages/FountainServiceKit-*`).

Why this works
- Faster: generator runs once per service (core); the server target compiles quickly with a small graph.
- Non‑destructive: manifest remains stable; specs stay curated under `Packages/FountainSpecCuration/openapi` (symlinked into cores). OpenAPI curability is preserved.
- Deterministic: one place per service for spec/config; servers are simple and testable.

Where
- Editor core: `Packages/FountainApps/Sources/fountain-editor-service` (owns spec + generator config).
- Editor server: `Packages/FountainApps/Sources/fountain-editor-service-server` (handlers + main).
- Seeder for this pattern’s prompt: `Packages/FountainApps/Sources/service-minimal-seed`; wrapper script: `Scripts/apps/service-minimal-seed`.

Maintenance
- When adopting the pattern in a service:
  - Create `<service>-service` core target, move spec/config there, and add `filter.paths`.
  - Remove generator plugin from `<service>-service-server`; depend on the core.
  - Add or update a thin wrapper script under `Scripts/dev/<service>-min` with `build|run` only.
  - Add focused handler tests; avoid workspace‑wide builds during TDD by using `--target`/`--filter`.

Prompt persistence (authoritative)
- The “Service‑Minimal Targeted Builds” Teatro prompt is persisted in FountainStore.
- Corpus: `service-minimal`; page: `prompt:service-minimal`.
- Seeder: run `Scripts/apps/service-minimal-seed` to (re)seed; fetch with `CORPUS_ID=service-minimal SEGMENT_ID='prompt:service-minimal:teatro' swift run --package-path Packages/FountainApps store-dump`.
- Facts: `SEGMENT_ID='prompt:service-minimal:facts'` contains services and invariants for auditing.

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

Rationale (why this is a hard rule)
- Concurrency safety: CoreMIDI’s C API relies on callbacks with undefined threading semantics and non‑Sendable types. Under Swift 6’s strict concurrency model, these APIs cannot be made safe without pervasive `@unchecked Sendable` and thread hops that would hide races and deadlocks. We require predictable actor isolation and value semantics for all transports.
- UI stability: Historical failures included hangs in the UI thread when `midiserver` was unavailable or stalled (e.g., blocking inside `MIDIDestinationCreateInternal`). This violates our self‑healing UX and causes flaky demos/tests.
- Determinism and testability: Our MIDI robot and snapshot suites must run headless on CI. CoreMIDI is macOS‑only and daemon‑dependent; it is not reproducible on Linux or in sandboxed runners. Loopback and RTP/BLE achieve deterministic flows across platforms with recorded UMP.
- Portability: FountainKit targets macOS and Linux. CoreMIDI prevents Linux builds and complicates cross‑platform packaging. MIDI 2.0 transports (RTP/BLE) and Loopback keep the surface portable.
- Observability: Our stack records UMP to NDJSON and can replay end‑to‑end. CoreMIDI obscures the timing model and introduces host‑specific quirks that are harder to diagnose than our `midi2` abstractions.

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

FAQ
- “Can we keep CoreMIDI behind a flag for power users?” No. The flag surface leaks types and build‑graph edges into CI and local builds, undermining determinism. If strictly necessary for a separate product, move it to a separate repository.
- “How do we talk to external MIDI‑1 devices?” Use our MIDI 2.0 model with explicit downgrade/filters at the edges (BLE RTP peers or the sampler bridge). The internal model remains UMP‑first with journaled timing.
- “What replaces virtual endpoints?” Loopback transport with explicit identity; our tests and tools target identity strings and UMP, not CoreMIDI virtuals.

### Sidecar Exception (AudioKit lane) — BLE/RTP bridge for host apps

Context
- Some third‑party apps (e.g., AUM on iOS) only support MIDI 1.0 over BLE or RTP‑MIDI 1.0. While our stack is CoreMIDI‑free, macOS/iOS connection managers commonly rely on CoreMIDI for reliable BLE/RTP handshakes.

Policy
- It is acceptable to run a separate, opt‑in sidecar process that uses CoreMIDI (e.g., AudioKit/MIDIKit) to bridge BLE MIDI 1.0 and/or RTP‑MIDI 1.0 for external hosts. This sidecar is NOT linked into FountainKit and MUST live in a separate product/repo.
- Communication between FountainKit and the sidecar happens over process boundaries (HTTP/IPC/UDP). No CoreMIDI types leak into this repository.

Guardrails
- Sidecar must be optional; default developer experience remains CoreMIDI‑free.
- Scripts may start/stop the sidecar, but package graphs in this repo MUST NOT gain a CoreMIDI dependency.
- Document the control protocol/ports. Prefer a tiny local HTTP control surface for selecting target BLE device name or RTP session parameters.

Operator usage
- Start sidecar: `Scripts/apps/midi-bridge` (looks for a configured bridge binary like an AudioKit‑based tool; see Scripts/AGENTS.md).
- Configure through env:
  - `BRIDGE_CMD` — absolute path to the sidecar binary/app bundle.
  - `BRIDGE_PORT` — local HTTP control port (default 18090) if the sidecar exposes one.
  - `BRIDGE_NAME` — advertised BLE device name (if the sidecar runs a Peripheral), or target BLE name (if it runs as Central).
- Fountain host/app selects the “CoreMIDI sidecar” transport when present and routes MIDI 1.0 bytes to it; otherwise it falls back to built‑in Loopback/RTP‑MIDI 2.0.

Why this exception exists
- It unblocks real instruments and DAWs (AUM, AudioUnits, etc.) that only speak BLE/RTP MIDI 1.0 while keeping our Swift 6 codebase CoreMIDI‑free and portable.

---

## MIDI 2.0 Everywhere (Concept)
Every interactive surface is a MIDI 2.0 instrument. The canvas, nodes, inspectors, and monitors may advertise a MIDI‑CI identity and optional Property Exchange so external tools can introspect and set state deterministically.

- Identity: stable names (`<product>#<instanceId>`) and MIDI 2.0 endpoints via our `midi2` transports (RTP/BLE). CoreMIDI is prohibited.
- State mapping: small PE schemas per surface (e.g., canvas: `zoom`, `translation.x/y`; stage: `page`, `margins.*`, `baseline`). GET is deterministic; SET applies and notifies.
- Topology: begin with one group/function block per canvas; promote per‑node blocks as needed.
- Transport‑agnostic: rendering and composition remain independent of MIDI; instrument mode is additive and optional.

### Facts‑Factory Instrument (runtime authoring)

What
- A built‑in MIDI‑CI instrument exposed by the host (when `HOST_ENABLE_FACTS_FACTORY=1`) that accepts an OpenAPI document and returns/seeds agent facts. This mirrors the Tools Factory HTTP flow entirely over MIDI 2.0.

Property surface
- `facts.from_openapi.submit` (writable, json)
  - Input: `{ agentId: string, corpusId?: string="agents", seed?: boolean=true, openapi?: object|string, specURL?: string }`
  - Behavior: generates facts from OpenAPI, optionally seeds FountainStore, replies with facts JSON.

How
- Start host: `Scripts/dev/agent-host run` (defaults enable Facts‑Factory).
- Send PE SET with the JSON envelope above; host replies with NOTIFY `{ status, body }` where `body` is the facts JSON (or an error object).
- Gateway then serves `/.well-known/agent-facts` for the `agentId` once seeded.

Notes
- Prefer `specURL` for large specs; `openapi` inline accepts either a JSON object or a YAML/JSON string.
- Enable/disable via `HOST_ENABLE_FACTS_FACTORY=1|0`. Agent id for this instrument defaults to `fountain.coach/agent/facts-factory/service` and can be overridden with `FACTS_FACTORY_AGENT_ID`.

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
## Swift 6 Concurrency + Focus Guardrails (Authoritative)

Why
- Swift 6 actor isolation is strict. Older GCD patterns lead to races and flaky focus. We standardize main‑actor UI and deterministic focus backed by PB‑VRT tests.

Rules
- UI code is `@MainActor`. Prefer `await MainActor.run { … }` over `DispatchQueue.main.async { … }`.
- Handlers are `@Sendable` and must not touch UI or non‑Sendable state. Hop to `Task { @MainActor in … }` before using `NSApp`/`NSWindow` or mutating `@Published`.
- No `Task.detached` in app/UI code. Use structured tasks bound to actors.
- No new `@unchecked Sendable` in app/UI targets. In services, isolate via actors or event‑loop contexts and document rationale.

Responder chain (deterministic)
- Text inputs that must take focus use an AppKit bridge (NSViewRepresentable) with a stable identifier and `window.makeFirstResponder`.
- Apps launched from Terminal call `NSApplication.shared.activate(ignoringOtherApps: true)` during bootstrap.
- PB‑VRT focus tests are required for new input surfaces; never land focus changes without tests.

Lint (CI)
- Concurrency: `! rg -n '\\bDispatchQueue\\.main\\.async\\b' -S Packages MIDI2InstrumentLab`, `! rg -n '\\bTask\\.detached\\(' -S`.
- CoreMIDI: `! rg -n '\\bimport\\s+CoreMIDI\\b|\\bMIDI(Client|Source|Destination|Port|Send|Received)' -S | rg -v '^Sidecar/|^External/'`.
- Unchecked Sendable in UI: `! rg -n '@unchecked\\s+Sendable' -S Packages/*UI* Packages/FountainApps MIDI2InstrumentLab`.

Reference
- FocusKit utility: `MIDI2InstrumentLab/Sources/FocusKit/` provides a reusable first‑responder TextField and a small focus helper. Reuse/port for other apps.

## GUI Surfaces — Event Graph, Not Widget Toolkit (New Work)

Intent
- New instruments and demos should be built on our own event graph and rendering layers, not on Apple’s widget toolkits. We keep a thin OS host (NSApplication/NSWindow/NSView) where needed, but the “UI” lives in our graph.

Rules (new work only)
- No new SwiftUI views in instrument surfaces. Existing SwiftUI apps (PatchBay, MemChat, QuietFrame, etc.) are grandfathered; future instruments must not add new SwiftUI entry points.
- AppKit is allowed only as a host: `NSApplication`, `NSWindow`, and a minimal `NSView` (or `FGKRootView`/MetalViewKit view) that forwards OS events into our event graph. Do not add new AppKit widgets (e.g., `NSTextField`, `NSButton`) for instrument interaction.
- Instruments expose their surface via:
  - the MetalViewKit / Canvas graph, or
  - the FountainGUIKit graph (`FGKNode` + `FGKEvent` + properties),
  and are addressed via specs + facts (OpenAPI + PE), not via framework‑specific controls.
- Specs and prompts remain the source of truth:
  - Teatro prompt in FountainStore (`prompt:<app-id>:teatro` + `:facts`).
  - OpenAPI spec under `Packages/FountainSpecCuration/openapi/v1`.
  - Facts generated via `Scripts/openapi/openapi-to-facts.sh`.

Enforcement
- For new instruments added to `Tools/instruments.json`, the default expectation is:
  - event‑graph based surface (FountainGUIKit or MetalViewKit),
  - no SwiftUI in the instrument view path,
  - NSView used as a thin host only.
- Agents should prefer reusing existing canvases (PatchBay, MIDI2InstrumentLab, FountainGUIKit demo host) rather than introducing new SwiftUI windows.

## Automated Audit — Agent Tasks (Run Every Session)

Intent
- Make Swift 6 concurrency/focus hygiene and corpus discipline automatic. The agent performs these tasks at session start without asking the operator.

Tasks (authoritative)
- History audit (full git history): produce a summary of concurrency/focus patterns.
  - Command: `Scripts/ci/history-audit.sh`
  - Output: `Tools/history-audit.txt` (commit counts, first/last sighting) and a repo snapshot of current matches.
- Repo scan + patch queue refresh:
  - Command: `rg -n "\\bDispatchQueue\\.main\\.async\\b|\\.focused\\(|makeFirstResponder\\(|firstResponder\\b|fieldEditor\\(|@Sendable|@unchecked\\s+Sendable" -S`
  - Update `Tools/concurrency_patch_queue.md` with file‑level actions (replace GCD, add FocusKit bridge, PB‑VRT tests).
- Lints (must pass before landing changes):
  - `bash Scripts/ci/lint-concurrency.sh`
- PB‑VRT focus check for active app:
  - Example (Lab): `make -C MIDI2InstrumentLab lab-pbvrt`
- Optional org‑wide audit (when `gh` is configured):
  - `gh api -X GET /search/code -f q='org:Fountain-Coach "DispatchQueue.main.async" language:Swift' -q '.total_count'`
  - Produce `Tools/org-audit.md` with counts/links.

Agent expectations
- Do not ask the operator to paste logs; run the scripts locally, analyze outputs, and patch.
- Do not introduce prompts or facts into code; keep guidance in FountainStore.
- Only claim “green” after lints + PB‑VRT tests pass locally.
