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
