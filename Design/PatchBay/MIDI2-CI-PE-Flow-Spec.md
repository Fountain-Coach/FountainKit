# PatchBay — MIDI 2.0 CI/PE Flow Spec

What
- A product and editing spec for modeling MIDI 2.0 Capability Inquiry (CI) and Property Exchange (PE) as a flow network on an infinite canvas in PatchBay.

Why
- CI/PE introduces discoverable function blocks, profiles, and JSON properties alongside UMP musical data. Treating them as first‑class nodes and typed edges makes session control, mapping, and monitoring deterministic, editable, and CI/PE‑correct.

Scope
- Canvas graph: nodes, ports, edges, overlays, and inspector semantics.
- Editing flows: discover/attach, profile enable, PE get/set/subscribe, UMP↔PE mappings.
- Does not change service OpenAPI; this spec governs the app’s flow model and UI.

Where (code anchors)
- App: `Packages/FountainApps/Sources/patchbay-app/**`
- Flow bridge: `Packages/FountainApps/Sources/patchbay-app/FlowBridge.swift`
- Canvas: `Packages/FountainApps/Sources/patchbay-app/Canvas/**`
- Service OpenAPI (reference only): `Packages/FountainApps/Sources/patchbay-service/openapi.yaml`

## Model — Nodes, Ports, Edges

Nodes (kind → purpose)
- `transportEndpoint` — A physical/virtual MIDI endpoint (USB/RTP‑MIDI/DAW). CI negotiates here; UMP streams originate/terminate.
- `functionBlock` — Device function block (MIDI 2.0 concept). Profiles/PE domains attach here.
- `profile` — A configured MIDI‑CI profile (e.g., DrawbarOrgan v1.0) attached to a `functionBlock`.
- `propertyDomain` — PE namespace (e.g., `pe:amsynth`). Encapsulates related JSON properties.
- `property` — A single PE path (e.g., `filter.cutoff`). Supports get/set/subscribe/notify.
- `mapper` — A signal transformer (UMP→PE, PE→UMP, PE→PE) with params: `scale`, `offset`, `curve`.
- `monitor` — A sink for UMP/PE streams with timeline/log UI.

Audio pipeline primitives (for intent→UMP)
- `audioInput` — Microphone/stream source; emits audio for analysis. Ports: left `in` (optional), right `out` (audio).
- `analyzer` — DSP/ML feature extractor (pitch/voicing/onset). Ports: left `in` (audio), right `out` (intent).
- `noteProcessor` — Real‑time note/gain/DC/legato smoothing; converts intent to UMP. Ports: left `in` (intent), right `umpOut`.

Ports (deterministic order)
- Inputs (left): `in`, `umpIn`, `ciIn`, `peIn` (if present). Order top→bottom.
- Outputs (right): `out`, `umpOut`, `ciOut`, `peOut` (if present). Order top→bottom.
- Property verbs: property nodes expose `get`, `set`, `sub` (inputs) and `notify` (output) as UI affordances; links encode the verb.

Edges (typed)
- `ump` — UMP musical data. Label: `G:<n> Ch:<m> {Note|CC|Pitch…}`. Color: musical.
- `ci` — Capability Inquiry control (negotiate/profiles/PE enable). Color: control.
- `pe` — Property path link with verb. Label: `pe:<namespace>.<path> [get|set|sub|notify]`.
- `map` — Mapper wiring; label carries `scale`, `offset`, `curve`.

## Canvas & Overlays

- Infinite canvas, grid snap; major/minor grid as today.
- UMP group lanes (optional overlay): light vertical bands G0–G15, shown when UMP edges are present or on toggle.
- Selection: marquee and per‑node; delete via Backspace/Forward Delete or drag to the trash target.
- Trash target: always on bottom‑right; hover highlight and puff animation on delete.
 - Zones overlay (optional): soft groupings for Host / Device A / Device B to clarify topology and CI/PE attachment points.

## Inspector (Right Pane)

Tabs (segmented)
- Instruments — list + per‑instrument properties (from service schema).
- Links — suggestions, applied links, run log.
- Rules — local checks (fit/center, pane width policy) backed by RulesKit later.
- Vendor — Vendor identity CRUD.
- Corpus — Snapshot summary + store save/load. Include compact evidence line: `Instruments: N [tri K, quad Q, chat C, coremidi E] · Links: L [property P, ump U]` with Copy and Refresh.
- Chat — Assistant seeded with “What’s in the corpus?”; uses existing Planner/Gateway wiring.

Stellwerk (control plane)
- Throughout the spec, the term “Stellwerk” is preferred for the control plane (discovery, routing, corpus snapshots) instead of “Control Tower”, aligning with theatre terminology.

## Editing Flows (reference)

1) Discover + attach
- Action “Discover CI” on `transportEndpoint` queries function blocks; user drags discovered `functionBlock` to canvas; app auto‑wires `ci` link.

2) Enable a profile
- Drag `profile` onto a `functionBlock`; app posts `ci profile enable` and persists state; inspector reflects enabled profiles.

3) PE round‑trip
- From inspector, choose domain+property; `Get` writes last value to property node, `Set` opens inline editor; `Subscribe` spawns a property node with `notify` wiring to a `monitor`.

4) Mapping controllers to properties
- Wire UMP CC/Note via `mapper` to `property.set` with `scale/offset/curve`; edge kind becomes `map`.

5) PE→UMP (state‑driven audition)
- Wire `property.notify` to `mapper` and then to `umpOut` for an audition/feedback loop.

## Graph Grammar (app‑side)

Node JSON (app-internal)
- `id: string`, `kind: string`, `title?: string`, `x:int`, `y:int`, `w:int`, `h:int`
- `ports: [{ id:string, side:"left|right", dir:"in|out", type:"data|ump|ci|pe" }]` (deterministically ordered)

Edge JSON (app-internal)
- `id: string`, `kind: "property|ump|ci|map"`, `from: "nodeId.portId"`, `to: "nodeId.portId"`
- `label?: string` (group/channel for UMP, verb for PE, params for map)

Persistence
- Export/import remains the service’s `GraphDoc` shape; app maps ports deterministically and adds verbs/labels when rendering.

## Acceptance
- Ports order stable across all creation paths (drop, double‑click, seed).
- Delete works via keys, context menu, and trash drag.
- Corpus evidence present and copyable in Instruments/Corpus tabs; Chat tab available.
- No OpenAPI/service changes required.
 - CI etiquette honored for MIDI‑CI/PE: transactions use TIDs, large messages fragment/reassemble, and PE subscribe/notify status is surfaced in the inspector.
 - Audio pipeline available: `audioInput → analyzer → noteProcessor → ump` fan‑out supported to multiple transport endpoints.

---

Versioning
- Store this document as the canonical flow spec; minor iterations update this file.

Owner
- PatchBay App maintainers. Please link changes from PRs touching flow nodes, inspector, or FlowBridge.

© 2025 Contexter alias Benedikt Eickhoff — internal spec (do not publish externally)
