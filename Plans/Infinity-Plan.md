# Infinity Workbench — Implementation Plan

Infinity is the forward “instrument workbench” surface: an infinite, SDLKit‑hosted canvas that runs directly on our own graph and transform math. This plan defines how we take Infinity from concept to a first‑class Fountain instrument without dragging legacy UI stacks along.

Infinity v1 is intentionally narrow: a single SDLKit window, instant launch from a prebuilt binary, no control‑plane boot, and a clean path to full instrument status (spec, facts, prompt, MIDI 2.0 reachability, tests).

## Goals

- Provide a fast, cross‑platform canvas workbench (“Infinity”) that does not depend on SwiftUI or AppKit in its interactive path.
- Reuse existing math and graph concepts (`Canvas2D`, node/edge graph) while keeping the implementation small and SDLKit‑centric.
- Make Infinity a first‑class instrument per `Design/INSTRUMENT_REQUIREMENTS.md`: spec‑backed, facts‑backed, PE‑addressable, and robot‑testable.
- Keep Infinity offline‑friendly: no servers are required to sketch or explore the canvas; services and MIDI routing are layered on top.

## Scope (Infinity v1)

- One SDLKit window titled `Infinity` with an infinite grid canvas.
- Camera controls: pan and zoom (mouse/trackpad + keyboard) using the canonical `Canvas2D` transform.
- Basic node/edge graph: rectangular nodes on the canvas with typed ports and simple selection/move/connect operations.
- No SwiftUI, no UIKit, and no direct AppKit usage inside the Infinity target; SDLKit is the sole GUI host.
- Optional sonification and full MIDI 2.0 CI/PE are planned but not required for the first runnable version.

Paths:
- Canvas math: `Packages/FountainApps/Sources/MetalViewKit/Canvas2D.swift`.
- SDLKit host: `External/SDLKit/Sources/SDLKit/Core/*`, examples under `Packages/SDLExperiment/Sources/SDLComposerExperiment/*`.
- Instrument requirements: `Design/INSTRUMENT_REQUIREMENTS.md`.

## Phase 1 — Canvas Core Extraction

What
- Treat `Canvas2D` as the canonical doc↔view transform for all infinite canvases (PatchBay, Infinity, future surfaces).
- Introduce a small, UI‑free graph model suitable for SDLKit rendering and instrument wiring.

Steps
- Make `Canvas2D` depend only on CoreGraphics (no AppKit); document its role in `MetalViewKit/AGENTS.md`.
- Add a minimal graph core (new types, or a refactor of existing ones) that does not depend on SwiftUI:
  - `InfinityNode { id, title, x, y, w, h, ports }`.
  - `InfinityEdge { fromNodeId, fromPort, toNodeId, toPort }`.
  - `InfinityScene`/`InfinityVM` with methods for adding/removing/moving nodes and edges, and for snapping to the grid.
- Keep this core free of rendering concerns and UI frameworks so both SDLKit and MetalViewKit can consume it.

## Phase 2 — SDLKit Infinity Runtime

What
- A new executable `infinity` target that opens an SDLKit window, runs an event loop, and renders the canvas using `Canvas2D` + the graph.

Steps
- Add an `infinity` executable target in `Packages/FountainApps/Package.swift`:
  - Dependencies: `SDLKit` (guarded by `FK_USE_SDLKIT=1`), the canvas/graph core, optional `FountainAudioEngine` for future sonification.
  - No dependency on SwiftUI or AppKit.
- Implement `Sources/infinity/main.swift`:
  - Create `SDLWindow` with a neutral background; create `SDLRenderer`.
  - Initialize `Canvas2D` with default zoom/translation and an empty `InfinityScene`.
  - Main loop:
    - Poll SDL events, map mouse/trackpad/keyboard into `Canvas2D.panBy` and `Canvas2D.zoomAround`.
    - Update selection and node positions in `InfinityScene`.
    - Clear renderer, draw grid lines and nodes using SDL primitives (`drawLine`, `drawRectangle`), then present.
- Wire a launcher script `Scripts/apps/infinity` that:
  - Builds `infinity` once on demand (`--build`) and otherwise execs the binary directly with `FK_USE_SDLKIT=1`.
  - Runs Infinity in offline mode by default (no servers).

Constraints
- SwiftUI and UIKit are prohibited in the Infinity target.
- AppKit usage must not appear in Infinity code; any macOS specifics are handled inside SDLKit itself.

## Phase 3 — Instrumentization (Spec, Facts, Prompt)

What
- Make Infinity a first‑class Fountain instrument with a spec, facts, prompt, and reachable properties.

Steps
- OpenAPI spec:
  - Add `Packages/FountainSpecCuration/openapi/v1/infinity.yml`.
  - Define operations for:
    - GET/SET canvas properties (`canvas.zoom`, `canvas.translation.x`, `canvas.translation.y`, `grid.minor`, `grid.majorEvery`).
    - Listing and (optionally) mutating nodes/edges in the Infinity graph.
- Facts:
  - Extend `Tools/openapi-facts-mapping.json` with `infinity.yml:fountain.coach/agent/infinity/service`.
  - Extend `Scripts/openapi/openapi-to-facts.sh` to generate facts for Infinity.
  - Seed facts into FountainStore (`facts:agent:fountain.coach|agent|infinity|service` in corpus `agents`).
- Teatro prompt + corpus:
  - Add a small `infinity-seed` executable in `Packages/FountainApps/Sources/infinity-seed` that writes:
    - `prompt:infinity:teatro` — textual description of the Infinity canvas, controls, and invariants.
    - `prompt:infinity:facts` — structured JSON for instruments, properties, and invariants.
  - Wire `Scripts/apps/infinity-seed` as a convenience wrapper.
  - On boot, Infinity fetches and prints its prompt like other instruments (no inline prompt text in code).

## Phase 4 — Tests and Robot Coverage

What
- Validate that Infinity behaves as defined by its spec, prompt, and facts, both numerically and visually.

Steps
- Canvas/graph tests:
  - Add tests under `Packages/FountainApps/Tests/InfinityTests` to cover:
    - `Canvas2D.panBy` and `zoomAround` invariants (follow‑finger pan, anchor‑stable zoom, clamped zoom).
    - Node placement, movement, and edge creation in `InfinityScene`, including grid snapping.
- Instrument tests:
  - Add tests that call Infinity’s HTTP surface (or an in‑process handler) according to the OpenAPI spec:
    - Set canvas properties and assert internal state matches.
    - (Later) list and mutate nodes/edges through spec‑defined operations.
- Robot/snapshot tests (future):
  - Use SDLKit’s screenshot facilities (raw or PNG) to capture the Infinity canvas for a known scene and compare against baselines.
  - Connect Infinity to `midi-instrument-host` once spec + facts are stable, and add a minimal CI/PE test that drives the canvas via PE and verifies the corresponding HTTP/state changes.

## Phase 5 — Sonification (Follow‑On)

What
- Treat Infinity as a playable instrument by mapping canvas interactions to sound.

Steps
- Use `FountainAudioEngine` (SDLKit‑backed) to:
  - Map pan/zoom gestures to continuous audio changes (e.g. filter, spatialisation, or spectral tilt).
  - Map node creation/deletion/connection to discrete events (percussive or melodic cues).
- Expose these mappings as properties in Infinity’s OpenAPI spec and facts (`sonify.*` fields) so they become testable and controllable via PE.
- Keep sonification optional and guarded behind flags in early iterations so the core canvas remains stable and fast.

## Maintenance Expectations

- This plan is authoritative for Infinity work. When Infinity’s scope or architecture changes, update this file in the same PR as the code.
- Root `AGENTS.md` treats Infinity + SDLKit as part of the core contract; changes that affect Infinity’s role as a first‑class instrument (spec, facts, prompt, CI/PE, tests) must keep `Plans/Infinity-Plan.md` in sync.
- Package‑local `AGENTS.md` files (for `MetalViewKit`, `FountainApps`, SDLExperiment) should reference this plan when adding or altering Infinity‑related targets.

