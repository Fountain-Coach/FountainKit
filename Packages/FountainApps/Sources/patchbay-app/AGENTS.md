## AGENT — patchbay-app (macOS)

Purpose
- PatchBay Studio — thin SwiftUI client for the PatchBay service.
- Instruments (MIDI‑CI endpoints) on a QC‑style canvas; properties are PE keys (uniforms for MVK).
- Operator‑friendly: shows instruments, runs CI/PE auto‑noodling, and will grow into AudioTalk‑style three‑pane UX.

Run
- Run app: `swift run --package-path Packages/FountainApps patchbay-app`
- Start service (separate terminal): `swift run --package-path Packages/FountainApps patchbay-service-server`
- One‑shot bind for CI (no block): `PATCHBAY_ONESHOT=1 swift run --package-path Packages/FountainApps patchbay-service-server`

Notes
- Client OpenAPI: `Sources/patchbay-app/openapi.yaml` tracks curated `openapi/v1/patchbay.yml`.
- Expect parity with service routes, including `/graph/suggest` for “Auto‑noodle (CI/PE)”.
- UX parity with AudioTalk: readiness verdict and segmented right pane (Instruments | Links | Vendor | Corpus) planned.
- Canvas: `Sources/patchbay-app/Canvas/**` contains a QC‑style canvas (grid with scale‑aware decimation, bezier edges, snap‑to‑grid, connect mode with Option fan‑out, double‑click to break).
- Add nodes:
  - Double‑click an instrument in the left list to add it to the canvas (with UMP and data ports) or use the toolbar’s “Add Node” for a generic node.
  - Toggle “Connect” in the toolbar to wire ports; hold Option to fan‑out one output to multiple inputs; double‑click an input port to break.
- Links inspector:
  - Suggestions: Refresh and Apply/Apply All (auto‑noodling via `/graph/suggest`).
  - Applied links: Refresh and Delete (GET/DELETE `/links`).
- Tests (focused)
  - Service: `Tests/PatchBayServiceTests` (suggestions, vendor identity round‑trip).
  - App UI logic: `Tests/PatchBayAppUITests` (grid decimation, drag/snap, connect/fan‑out).
  - Run isolated builds/tests in Xcode or build per‑target to avoid cross‑package noise.

## Top‑Down Overview

- Purpose
  - Visual, deterministic MIDI 2.0 instrument patching (nodes = instruments, edges = UMP/property links) with a thin SwiftUI client for a typed OpenAPI service.
- Components
  - Service (OpenAPI): `Sources/patchbay-service/**` — instruments, links, discovery, store, corpus, vendor identity.
  - App UI (SwiftUI): `Sources/patchbay-app/**` — Canvas (grid, snap, connect), Inspector (Instruments | Links | Vendor | Corpus), keyboard nudge, store save/load.
  - Client (OpenAPI): `Sources/patchbay-app/openapi.yaml` + `ServiceClient.swift` — suggest links, link CRUD, store GET/PUT, corpus snapshot.
- Runtime flow
  - Fetch instruments → add to canvas → connect (typed edges) → manage suggestions/applied links → save/load graphs → snapshot corpus.
  - Auto‑noodling is grounded in CI/PE; GraphDoc is the deterministic artifact (ETags via FountainStore).
- Dev/test
  - Build app: `swift build --package-path Packages/FountainApps -c debug --target patchbay-app`
  - Run app: `swift run --package-path Packages/FountainApps patchbay-app`
  - Run service: `swift run --package-path Packages/FountainApps patchbay-service-server`
  - Focused tests: `swift build --package-path Packages/FountainApps -c debug --target PatchBayAppUITests`
  - Snapshot tests write candidates to `/tmp/` if baselines are missing.

## Agent Builder Excurse — Learnings and Integration Plan

What It Likely Is

- A declarative “agent definition” layer on top of OpenAI’s latest APIs (Responses, Realtime, Tools/Actions, Files/Knowledge).
- You configure an agent (instructions, safety/policy gates, tools/actions, knowledge/files, memory/recall), then test and ship it with a hosted runtime.
- A React/Next.js front end that edits a typed agent spec and a backend that persists it and proxies to the platform APIs for runs, streaming, tool calls, and file search.

Building Blocks

- Instructions: system prompt + role policies (guardrails and style).
- Tools/Actions: typed endpoints via OpenAPI/JSON Schema (aka “Actions”). Auth is handled (API keys, OAuth) and the platform mediates tool-calls → HTTP.
- Knowledge: files and snippets stored server-side (vector/file search) exposed as a single “File Search” tool.
- Structured outputs: enforce JSON schemas so downstream code can trust responses.
- Memory: per-agent or per-session recall (stateful runs/threads).
- Debug + Preview: streaming runs, visibility into tool-calls and intermediate states.

Runtime Pattern

- Stateless requests (Responses API) or stateful threads/sessions for multi-turn workflows.
- The model plans; when it “calls a tool,” the platform emits a tool-call event (with typed args). The UI shows the call; the tool runs; results are fed back as new input; the run continues until completion — all streamable.
- Safety hooks (moderation/policy) and permission prompts around tool calls when needed (OAuth scopes, sensitive actions).

Why It Feels Modern

- Typed, declarative surface: define capabilities via OpenAPI/JSON Schema, not ad-hoc glue. The editor understands types, shows forms, and validates configs.
- First-class tools orchestration: tool calls are explicit, inspectable steps. Excellent for debugging and auditing.
- One runtime contract: everything funnels through a single Responses/Tools abstraction (text, JSON, files, realtime).
- Built-in knowledge + memory: avoids bespoke RAG scaffolding; you opt-in and get consistent retrieval behavior.
- Seamless human-in-the-loop: previews, approvals, and streaming logs lower the cost of iteration.

How It Competes (and Aligns) With PatchBay

- Competes on “graph-of-capabilities” UX: Agent Builder is a capability patcher, but textual/declarative, not a spatial canvas. PatchBay is a literal node/edge canvas for instruments and mappings.
- Shared philosophy: typed edges. In Agent Builder, edges are model→action calls with typed parameters. In PatchBay, edges are UMP/property links with typed ports. Both reject vague glue.
- Hosting + guardrails vs. on‑device: Agent Builder gives managed infra (auth, policy, previews). PatchBay gives live, local, deterministic control of instruments (MIDI 2.0, Metal views, timelines).

Where PatchBay Wins (Domain Strength)

- Real-time instruments: MIDI 2.0 (PE/CI), UMP mapping, anchored timelines, and visual patching ergonomics. This is beyond “agent config” — it’s performance-grade interactive graphing.
- Determinism and journal: graphs, ETags, reproducible sessions, UMP events — ideal for audio/composer workflows.
- Auto‑noodling grounded in device capabilities (CI/PE), not generic function matching.

What We Should Borrow

- Actions-first mindset: treat every PatchBay operation (save graph, suggest, link CRUD, corpus snapshot) as a typed Action. We already have OpenAPI; keep scoping and schemas tight.
- Structured outputs everywhere: keep JSON schemas for suggestions, links, vendor identity, and snapshots — no freeform payloads.
- Inline preview + approvals: in our Inspector, show “proposed operations” (like Apply Link, Save Graph) and surface diffs/ETags before applying.
- Tool auth + scoping: if PatchBay invokes external tools (renderers, storage), model them explicitly (OpenAPI + secrets) and scope operations per profile/session.

Synergy: Using Agent Builder With PatchBay

- Register PatchBay’s OpenAPI as an Action tool for an OpenAI Agent:
  - The agent can Suggest Links, Create/Delete Links, and Save/Load Graphs by calling our service.
  - The agent becomes a co-pilot in PatchBay, producing deterministic, typed changes the operator can accept.
- Compile GraphDoc → Agent presets:
  - A PatchBay scene can export a minimal “agent profile” (instructions + scoped actions) so users can jump between the canvas and a chat/voice agent that manipulates the same scene.

Near-Term Actions For Us

- Harden Actions: ensure PatchBay service spec exposes just-enough endpoints with tight schemas, good errors, and idempotency.
- UX parity for “approvals”: add a mini “run log” in the Links tab that shows which Actions just executed and the diff/ETag.
- Structured tests: snapshot baselines for port-compatibility coloring and connect flows (we planned this).
- Optional builder-like form: a small panel that lists “capabilities” (suggest, link, save, load) with typed forms and live try‑it — inspired by Agent Builder, within our domain.

Bottom line

Agent Builder is a typed, managed agent orchestration surface; PatchBay is a typed, visual instrument/mapping surface. They’re complementary — adopt its declarative, audited tool model; keep our real-time, canvas-first strengths.

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
