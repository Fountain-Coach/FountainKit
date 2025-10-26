## AGENT — patchbay-app (macOS)

Purpose
- PatchBay Studio: a thin SwiftUI client for a typed PatchBay service. Nodes are MIDI 2.0 instruments (CI/PE); edges are typed UMP/property links.

Quick Start
- Run service: `swift run --package-path Packages/FountainApps patchbay-service-server`
- Run app: `swift run --package-path Packages/FountainApps patchbay-app`
- One‑shot bind (smoke): `PATCHBAY_ONESHOT=1 swift run --package-path Packages/FountainApps patchbay-service-server`

Key Features
- Canvas: grid with scale‑aware decimation, snap‑to‑grid, QC‑style wiring (click output → input), Option fan‑out, double‑click to break.
- Add nodes: double‑click an instrument in the left list; or use toolbar “Add Node” (adds data ports by default; UMP ports when available).
- Links inspector: Refresh/Apply/Apply All suggestions (`POST /graph/suggest`); list applied links (GET/DELETE `/links`).
- Keyboard nudge: arrow keys move selected nodes by one grid step; Option moves 5 steps.
- Store save/load: save current scene to FountainStore; list and load stored graphs.

APIs (client copy)
- Spec: `Sources/patchbay-app/openapi.yaml` (mirrors curated `openapi/v1/patchbay.yml`).
- Core routes: `/instruments`, `/graph/suggest`, `/links`, `/store/graphs`, `/store/graphs/{id}`, `/corpus/snapshot`, `/admin/vendor-identity`.

Tests (focused)
- App UI logic: `Tests/PatchBayAppUITests` (grid decimation, fit/center, drag/snap, connect/fan‑out, nudge, snapshots).
- Service handlers: `Tests/PatchBayServiceTests`.
- Build per‑target to avoid workspace noise.

## Top‑Down Overview

- Components
  - Service (OpenAPI): instruments, links, discovery (CI/PE), store, corpus, vendor identity. Path: `Sources/patchbay-service/**`.
  - App (SwiftUI): canvas/editor, inspector, keyboard, store integration. Path: `Sources/patchbay-app/**`.
  - Client: `openapi.yaml` + `ServiceClient.swift` generate typed calls for suggest, link CRUD, store GET/PUT, snapshots.
- Runtime Flow
  - List instruments → add to canvas → wire ports (typed) → apply suggestions → save/load graphs → snapshot corpus.
  - GraphDoc = deterministic artifact (ETags via FountainStore).
- Dev/Test Commands
  - Build app: `swift build --package-path Packages/FountainApps -c debug --target patchbay-app`
  - Run tests (target): `swift build --package-path Packages/FountainApps -c debug --target PatchBayAppUITests`
  - Snapshot tests write candidates to `/tmp/` when baselines are missing.

## Agent Builder Excurse — Learnings and Integration Plan

- What it is
  - Declarative agent configuration on top of Responses/Realtime + Actions (OpenAPI/JSON Schema) + Knowledge (files) + Memory.
  - Typed plan→tool‑call loop with hosted runtime, previews, and policy gates.
- Building blocks
  - Instructions, Policies; Actions (OpenAPI/JSON Schema with auth); Knowledge; Structured outputs; Memory; Debug/Preview.
- Runtime pattern
  - Stateless or stateful runs; model emits typed tool calls; platform executes and streams results back.
- Why it feels modern
  - Typed, auditable tools; one runtime contract; built‑in retrieval and memory; human‑in‑the‑loop by design.
- Alignment vs PatchBay
  - Shared typed‑edge philosophy. Agent Builder is declarative and hosted; PatchBay is spatial, real‑time, and deterministic (MIDI 2.0, UMP).
- Borrow for PatchBay
  - Actions‑first (keep OpenAPI tight); structured outputs; inline approvals/diffs; explicit tool auth + scoping.
- Synergy
  - Register PatchBay as an Action tool for agents (suggest, link CRUD, store); export GraphDoc → agent preset for chat/voice control of the same scene.
- Near‑term actions
  - Harden Actions; add Links run‑log with diffs/ETags; snapshot baselines for port‑compat; optional “capabilities” form in Inspector.
- Bottom line
  - Use Agent Builder’s declarative, audited model; keep PatchBay’s real‑time, canvas‑first strengths.

## Vision — Why PatchBay Studio

- Why this app
  - Turn interactive instrument ideas into deterministic, inspectable, automatable graphs. QC ergonomics with MIDI 2.0 CI/PE reality.
- Value to FountainAI
  - Spec‑first control surface; deterministic artifacts (ETags, Store, Secrets); shared types across kits; bounded action space for safer AI.
- Value to AudioTalk
  - Operator home: wire capture/transform/render; reproducible sessions with journals/anchors; fast iteration via auto‑noodling.
- Value to LLM workflows
  - Grounded autonomy (typed instruments/links); deterministic feedback via ETags; compact Corpus for reliable RAG; explainable changes.
- Engineering guarantees
  - OpenAPI‑first; generated types; deterministic IO; focused tests; one‑shot service for CI smoke.
- QC heritage, modernized
  - AppKit/SwiftUI editor; Metal/CI visuals; MIDI 2.0 I/O; inline editing; clips/prefabs; macros.
- Business & identity
  - Vendor identity + sub‑IDs in SecretStore; productizable graphs.
- Why now / success
  - Robust operator bay; no spec drift; structured AI collaboration. Success = artists patch quickly, CI is green, diffs explain changes.
- In one line
  - PatchBay Studio: deterministic, AI‑assisted, MIDI 2.0‑native patching under OpenAPI control.

## Vision — Why PatchBay Studio

Why This App

PatchBay Studio exists to turn “ideas about interactive instruments” into deterministic, inspectable, and automatable graphs. It gives us a modern Quartz Composer–style workspace where nodes are MIDI 2.0 instruments (with real, typed properties via PE and introspection via CI), and “noodles” are explicit mappings (UMP→property and property↔property). It’s the illustration and verification bay for AudioTalk and the wider Fountain stack: a place where you can see, test, and evolve behavior with high confidence — and where LLMs can safely co‑pilot rather than free‑solo.

What It Is

- A node‑graph “sketch tool” centered on MIDI 2.0: instruments expose typed property schemas (PE), endpoints are discovered (CI), and edges encode mappings with semantics (e.g., CC→parameter with range/curve).
- A service‑first product: OpenAPI governs everything (suggestions, links, store, corpus, vendor identity). The SwiftUI app is a thin client with a robust canvas and inspector.
- A lab for auto‑noodling: the service proposes links from real capabilities (intersection of CI/PE), not guesses. The app lets operators accept, inspect, or delete those links.

Value to FountainAI

- Spec‑first control surface: Forces every behavior to be an API, versioned and linted. Tools Factory, Gateway, and clients all benefit from that stability.
- Determinism and audit: Graphs, mappings, and identity round‑trip through FountainStore. Vendor identity and sub‑IDs live in SecretStore. Everything has ETags and can be snapshotted into a Corpus for LLM context.
- Shared models, no duplication: Instruments and links are canonical types usable by gateway orchestration, tools registration, and studio UIs.
- Safer AI control: The LLM is grounded in a bounded action space: “suggest links,” “patch instrument defaults,” “save a graph,” “create snapshot.” Fewer foot‑guns, more explainability.

Value to AudioTalk

- Patchbay = operator home: It is the live workspace where you wire capture, transforms, samplers, and renderers; where UMP streams meet instrument properties with correct ranges and curves.
- Reproducible artistry: You can freeze a session to a graph, later re‑hydrate, and get the same behavior. Journaled timelines and anchors keep it navigable.
- Rapid iteration, no mystery: Auto‑noodling seeds reasonable mappings; the artist can keep or tweak. Graphs are explicit artifacts, not opaque “project” blobs.
- Future editors plug in: Cue sheets, LilyPond apply, and notebook‑like timeline events naturally extend from the same graph and corpus.

Value to LLM Workflows

- Grounded autonomy: The model sees instruments (with types and constraints), can run discovery, and propose links. It doesn’t hallucinate data paths; it composes valid ones.
- Deterministic feedback loop: Every accepted suggestion mutates a graph doc with an ETag; the LLM can diff the world, re‑plan, and cite exact changes.
- Corpus as context: The corpus snapshot is the LLM’s “world state” — instruments, schemas, mappings, vendor identity. RAG becomes reliable because the data is small, typed, and curated.
- Explainable by construction: Each link encodes intent (reason, confidence, mapping function). It’s trivial to justify why a change is safe.

Engineering Guarantees

- OpenAPI‑first: No code paths without specs. Apple’s Swift OpenAPI Generator keeps generated types/stubs out of the repo and always in sync.
- Deterministic IO: FountainStore holds graph docs; SecretStore guards vendor identity. ETags and timestamps defend against race conditions and stale updates.
- Testable UI: The canvas is snapshot‑tested. Grid decimation, wiring compatibility colors, and drag/snap have focused tests. The service runs in one‑shot mode for CI smoke.

QC Heritage, Modernized

- Same ergonomics, modern substrate: AppKit/SwiftUI editor, Metal/CI for visuals, MIDI 2.0 for I/O. Inline editing, Option fan‑out, double‑click to break, profile/debug overlays — the right affordances for flow.
- Clips → Prefabs: Selections can become reusable snippets. The patch library can be indexed and described, keeping velocity high.
- Macro/hierarchy: As the graph grows, subgraphs and published ports mirror QC’s compositional power without legacy tech.

Business and Identity

- Vendor identity management: We store manufacturer/family/model/revision securely, and we can allocate sub‑IDs per instrument instance. This supports commercial distribution and licensing.
- Productize graphs: A curated graph becomes an asset you can package, test, and sell, not a fragile demo.

Why This Matters Now

- AudioTalk needs a dug‑free, robust bay to prove the promise of QC’s UX with modern MIDI 2.0 and AI. We’ve repeatedly hit friction getting there; this is the systematized answer.
- Spec drift kills velocity. By putting the app behind APIs and leaning on generation, we converge on one rhythm: edit spec → build → run → test → snapshot.
- LLMs need constraining structure to shine. PatchBay is that structure: small, typed, introspectable — perfect for co‑creation without chaos.

What Success Looks Like

- Everyday use: Artists open PatchBay, discover instruments, accept a few smart suggestions, and immediately get meaningful behavior. They can perform, iterate, and export — reliably.
- Stable build/test loop: CI boots the service, suggests links for a fixture set, applies them, and validates a canvas snapshot. No flaky steps, no manual fixes.
- LLM‑assisted sessions: “Wire my mic to this sampler with a gentle exp curve and gate at -18 dB” becomes a safe, verifiable action with a diff the user can accept — and undo.

In One Line

PatchBay Studio gives FountainAI and AudioTalk a deterministic, AI‑assisted, MIDI 2.0‑native patching environment — a modern, tested, and explainable place where instruments, mappings, and creativity meet under OpenAPI control.
