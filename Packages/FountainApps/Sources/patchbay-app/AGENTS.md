## PatchBay Studio — Agent Guide (macOS)

PatchBay Studio is a visual, deterministic patcher for MIDI 2.0 instruments. The app is a thin SwiftUI client that speaks to a typed PatchBay service over OpenAPI. Instruments (discovered via CI and described by PE) appear as nodes on a canvas; connections are explicit, typed links (property↔property and UMP→property). The goal is to make ideas concrete, inspectable, and repeatable — without mystery glue.

MIDI 2.0 everywhere: the canvas and nodes can run in “instrument mode” and publish CoreMIDI virtual endpoints (protocol 2.0) with a small Property Exchange schema (canvas: `zoom`, `translation.x/y`; stage: `page`, `margins.*`, `baseline`). Rendering remains transport‑agnostic; instrument mode is additive and optional.

Getting started is simple: start the service, then the app. By default, our dev scripts launch the service as part of the core control plane. If you prefer to run it by hand, you can do that too. The service exposes a small set of endpoints for instruments, graph suggestions, link CRUD, store, and corpus snapshots; the app surfaces these as focused tools in the right‑hand inspector.

### Quick start

Start everything with logs and readiness checks by running `bash Scripts/dev-up --check`. This brings up the core services, including PatchBay on `PATCHBAY_PORT` (defaults to 7090). Then launch the app with `swift run --package-path Packages/FountainApps patchbay-app`. Prefer to run the service manually? Use `swift run --package-path Packages/FountainApps patchbay-service-server` (it falls back to an ephemeral port if 7090 is busy and prints the bound port). For CI smoke, `PATCHBAY_ONESHOT=1` binds and exits.

### Using the canvas

The canvas is an infinite artboard with an adaptive grid. Use the Canvas menu to “Fit to View” (resets zoom and centering) and pick a grid density (e.g., 12/16/24 px minor; major every 5). Double‑click an instrument in the left pane to add it to the canvas (data ports always; UMP ports when available). To connect nodes, toggle “Connect” in the toolbar, click an output, then an input. Hold Option to fan‑out the same output to multiple inputs. Double‑click an input to break a connection. Arrow keys nudge the selection by one grid step; Option nudges by five.

### Links, actions, and logs

The Links tab offers two complementary tools. “Suggestions” retrieves proposed links from the service (CI/PE‑grounded auto‑noodling). You can preview the exact JSON of a proposed link before applying it, or apply all at once (with a confirmation). “Applied Links” lists the current links and lets you delete any. A run log summarizes changes (what ran, a short detail, and a simple diff like `links: 2→3`) so work remains auditable.

- Visual feedback: When you apply a property link, the matching edge on the canvas is added (if missing) and glows briefly so you can confirm the change at a glance. Wires added/removed in the Flow editor also mirror to the PatchBay service (Create/Delete Link), and the Links tab refreshes automatically.

### Saving and loading scenes

The Corpus tab includes store integration. You can save the current canvas to FountainStore under a chosen ID, list stored graphs, and load any back into the canvas. Under the hood, the app converts your nodes and edges into a `GraphDoc` and keeps positions, sizes, and links deterministic.

Agent presets. The Corpus tab also includes “Export Agent Preset…”. This writes a lightweight JSON file capturing:
- The PatchBay server `baseURL` used by the app.
- The current `GraphDoc` (your scene).
- A minimal set of PatchBay OpenAPI actions (operationIds) to enable chat/voice control of the same scene.

Use this file as a seed for agent tooling (or to register PatchBay actions in a gateway). The format is app‑local and intentionally simple — see `AgentPreset.swift`.

Export. Page-centric PDF export has been removed with the shift to an infinite artboard. A future export will snapshot the visible scene.

Teatro DSL workflow
Use Teatro’s Storyboard and MIDI 2.0 DSLs to produce deterministic previews and educational demos of PatchBay scenes. This gives us portable, CI‑friendly animations without touching app UI code. See `External/TeatroPromptFieldGuide/README.md` for the upstream prompt field guide and `External/TeatroFull` for the engine.

- Preview: export the current canvas as a sequence of Teatro Storyboard scenes (blank → nodes placed → links applied). Render animated SVG via `External/TeatroFull`.
- Sync audio: derive a `MIDISequence` from link events to drive `TeatroPlayerView` playback alongside frames.
- Teach/test: include concise storyboard snippets in docs and tests so agents can reason about intended flows before UI implementation.

PR checklist (app-side quick gate)
- Spec sync: run `bash Scripts/ci/check-patchbay-spec-sync.sh` and confirm InstrumentKind matches curated/service/app.
- Visuals: run `bash Scripts/ci/ui-smoke.sh` and verify RMSE within thresholds; rebaseline intentionally changed goldens with `bash Scripts/ci/ui-rebaseline.sh`.
- Prompt Field Guide tools: run `bash Scripts/ci/teatro-guide-smoke.sh` (idempotent) to register tools via ToolsFactory and invoke one endpoint through FunctionCaller; inspect `.fountain/artifacts/teatro-guide.*` for response + ETag.

### API surface (client copy)

The app’s OpenAPI document lives at `Sources/patchbay-app/openapi.yaml` and mirrors the curated spec at `Packages/FountainSpecCuration/openapi/v1/patchbay.yml`. Core routes: `/instruments`, `/graph/suggest`, `/links` (GET/POST/DELETE), `/store/graphs` and `/store/graphs/{id}` (GET/PUT), `/corpus/snapshot`, `/admin/vendor-identity`. The service copy is the source of truth during development; the curated spec governs schema reviews.

### Instrument Addition Checklist (app side)

Keep the app in lock‑step with the service when adding instruments.

- Mirror the curated spec: Edit `Sources/patchbay-app/openapi.yaml` to match changes made in `Packages/FountainSpecCuration/openapi/v1/patchbay.yml` (e.g., new `InstrumentKind` case, property schema fields/names).
- Regenerate types: `swift build --package-path Packages/FountainApps -c debug --target patchbay-app` (Apple’s generator writes to `.build/plugins/outputs/…/OpenAPIGenerator`).
- Verify UI: Run the app, ensure the new instrument appears in the left pane and its properties show under schema/links views as expected.
- Snapshot if UI changed: Add or update goldens under `Tests/PatchBayAppUITests/Baselines` and run the UI tests. Use `PATCHBAY_WRITE_BASELINES=1 swift run --package-path Packages/FountainApps patchbay-app` then `Scripts/ci/ui-rebaseline.sh` to commit updated images.
- Don’t hand‑edit generated Swift: Keep changes to `openapi.yaml`, `ServiceClient.swift`, and view code only.

### Tests

Focused tests live under `Tests/PatchBayAppUITests` and cover grid decimation, fit/center math, drag/snap, connect/fan‑out, keyboard nudge, and image snapshots. When a snapshot baseline is missing, tests write candidates to `/tmp/` for approval. Service handler tests sit under `Tests/PatchBayServiceTests`. To avoid workspace noise, build per‑target while iterating.

## Top‑down overview

The service (OpenAPI) exposes instruments, links, discovery (CI/PE), store, corpus, and vendor identity. It lives under `Sources/patchbay-service/**` and is started automatically by `Scripts/dev-up`. The app (SwiftUI) bundles the canvas/editor, inspector, keyboard handling, and store integration under `Sources/patchbay-app/**`. A local client (`openapi.yaml` + `ServiceClient.swift`) generates typed calls for suggestions, link CRUD, store GET/PUT, and snapshots.

At runtime you typically: list instruments, add them to the canvas, wire ports (typed), apply link suggestions, optionally refine/delete links, save to store, and export a corpus snapshot. The `GraphDoc` is your deterministic artifact (positions, sizes, and links) with ETags handled by FountainStore.

## Alignment with Engraver, ScoreKit, RulesKit, AnimationKit

PatchBay is the sketch bay that adopts the same foundations as our engraving stack:
- Flow supplies the node/wire editor. PatchBay’s grid is pixel‑based and tuned for interaction.
- Engraver is the print authority. PDF export is wired to NSView today and will route through Engraver next to preserve typography and page metrics 1:1.
- RulesKit encodes invariant checks (e.g., PageFit, MarginBounds, PaneWidthRange). PatchBay exposes a Rules tab and will call RulesKit for enforcement; CI blocks on failures.
- AnimationKit will unify timing (connect glow, selection pulse, zoom easing) behind a single, testable DSL.

## Flow adoption (AudioKit)

We embed AudioKit’s Flow NodeEditor as the node/wire editor inside our infinite artboard.
- Why: Flow provides a mature, efficient SwiftUI Canvas implementation with proper pan/zoom, marquee selection, node dragging, and typed ports (control/signal/midi/custom).
- Bridge: `FlowBridge.swift` maps our `EditorVM` nodes/edges ⇄ Flow `Patch`. Node moves snap to the mm grid; wire add/remove call our link service (best‑effort in the first pass).
- Transforms: we bind Flow’s `transformChanged` to PatchBay’s zoom/translation so the mm grid stays aligned under Flow’s content.
- Visual regression: existing goldens remain strict. We added goldens for multiple sizes; Flow integration must keep them green.

## Agent Builder: what we borrow, what we keep

OpenAI’s Agent Builder shows a clean pattern: declarative, typed actions (OpenAPI/JSON Schema), a single runtime contract (Responses/Realtime), built‑in knowledge/memory, and human‑in‑the‑loop previews. We keep our spatial, real‑time canvas and determinism, but borrow the discipline: actions‑first APIs, structured outputs, explicit approvals, and scoped auth. Two synergy points: register PatchBay as an agent tool (suggest, link CRUD, store) and export a minimal agent preset from a `GraphDoc` so artists can flip between canvas and chat/voice control of the same scene.

## Vision — why it matters

PatchBay turns interactive instrument ideas into deterministic, inspectable graphs. It’s QC ergonomics grounded in MIDI 2.0 reality (CI/PE, UMP), with OpenAPI keeping change under control. For FountainAI, it’s a spec‑first control surface with store‑backed artifacts and secrets‑backed identity; for AudioTalk, it’s the operator’s home where routing and behavior stay reproducible. For LLMs, it narrows the action space to typed, auditable changes and returns explainable diffs. Success looks like fast patching, green CI, and changes you can justify.

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

- AudioTalk needs a bug‑free, robust bay to prove the promise of QC’s UX with modern MIDI 2.0 and AI. We’ve repeatedly hit friction getting there; this is the systematized answer.
- Spec drift kills velocity. By putting the app behind APIs and leaning on generation, we converge on one rhythm: edit spec → build → run → test → snapshot.
- LLMs need constraining structure to shine. PatchBay is that structure: small, typed, introspectable — perfect for co‑creation without chaos.

What Success Looks Like

- Everyday use: Artists open PatchBay, discover instruments, accept a few smart suggestions, and immediately get meaningful behavior. They can perform, iterate, and export — reliably.
- Stable build/test loop: CI boots the service, suggests links for a fixture set, applies them, and validates a canvas snapshot. No flaky steps, no manual fixes.
- LLM‑assisted sessions: “Wire my mic to this sampler with a gentle exp curve and gate at -18 dB” becomes a safe, verifiable action with a diff the user can accept — and undo.

In One Line

PatchBay Studio gives FountainAI and AudioTalk a deterministic, AI‑assisted, MIDI 2.0‑native patching environment — a modern, tested, and explainable place where instruments, mappings, and creativity meet under OpenAPI control.
