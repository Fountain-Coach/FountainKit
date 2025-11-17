# Fountain Instruments — Requirements Checklist

This checklist defines what it means for a surface in FountainKit to be a **first‑class instrument**. Every new canvas, sampler, or GUI “instrument” must satisfy these requirements.

The goal is simple: a human and a robot should be able to discover the instrument, understand its properties, drive it over MIDI 2.0, and verify its behaviour end‑to‑end (UI and runtime) without guesswork.

## 1. Prompt and Facts (Teatro + FountainStore)

- Each instrumented app has a dedicated corpus in FountainStore (e.g. `fountain-gui-demo`, `mpe-pad-app`, `baseline-patchbay`).
- The corpus contains a **Teatro prompt page**:
  - Page id: `prompt:<app-id>` (for example `prompt:fountain-gui-demo`).
  - Segments:
    - `prompt:<app-id>:teatro` with kind `teatro.prompt` — human‑readable description of the surface, instruments, and invariants.
    - `prompt:<app-id>:facts` with kind `facts` — structured JSON: instruments, PE fields, ops, invariants.
- Prompts are written and updated only via small seeders (e.g. `mpe-pad-app-seed`, `fountain-gui-demo-seed`); apps read and print them at runtime but never embed them in code or docs.

## 2. OpenAPI Spec and Facts

- Every instrument surface has an authoritative OpenAPI spec under `Packages/FountainSpecCuration/openapi/v1`:
  - Example: `fountain-gui-demo.yml`, `patchbay.yml`, `metalviewkit-runtime.yml`.
- The spec is registered in `Scripts/openapi/openapi-to-facts.sh` so facts can be generated for a specific `agentId`:
  - Mapping: `<spec>.yml:fountain.coach/agent/<name>/service`.
- Facts for the instrument live in FountainStore:
  - Corpus: `agents`.
  - Collection: `agent-facts`.
  - Document id: `facts:agent:<agent-id>` (with `/` → `|` as needed).
  - Content: `protocol: "midi-ci-pe"`, `functionBlocks[*].properties[*]` with `mapsTo.openapi` entries for each operation.

## 3. MIDI 2.0 Reachability (Host and/or Endpoint)

An instrument must be reachable over MIDI 2.0 CI/PE in at least one of these ways:

- **Via MIDI Instrument Host + HTTP:**
  - Facts describe OpenAPI operations (`mapsTo.openapi`) that set/get the instrument’s properties.
  - `midi-instrument-host` is configured with `HOST_AGENTS` including the instrument’s `agentId`.
  - `AGENT_BASE_URL_*` points either to the app’s HTTP surface or to a shared runtime (for example `metalviewkit-runtime`).
  - MIDI‑CI PE GET/SET from the host must translate into HTTP calls that update the instrument’s state.

and/or

- **Via a MIDI 2.0 endpoint exposed by the app/runtime:**
  - The instrument registers a virtual endpoint (Loopback/RTP/BLE) and responds to MIDI‑CI Discovery + Property Exchange.
  - Property names in CI match the PE fields in facts (no ad‑hoc differences).

For visual instruments in MetalViewKit, the preferred pattern is facts → `midi-instrument-host` → `metalviewkit-runtime` → instrument state, with UI reading that state.

## 4. Shared Property Schema (GUI + Runtime)

- The GUI uses the same property names as the spec and facts, for example:
  - `canvas.zoom`, `canvas.translation.x`, `canvas.translation.y`, `canvas.rotation`.
- The GUI’s transform behaviour (pan/zoom/rotate) is defined in the Teatro prompt and implemented in code:
  - Follow‑finger pan: view‑space deltas map consistently into the transform.
  - Bounded zoom/rotation: values are clamped to documented ranges.
  - Any easing or animation is explicitly described (or explicitly absent, as in minimal demos).
- Runtime state mirrors the same schema when applicable:
  - For example, `metalviewkit-runtime` exposes `/v1/instruments/{id}/state` with a `properties` map for instrument state, and facts map PE fields onto that API.

## 5. Tests and Robot Coverage

- At least one test suite exists for each instrument that:
  - Drives the instrument via MIDI 2.0 CI/PE and/or HTTP according to facts.
  - Verifies properties and invariants:
    - Example: pan moves the canvas by expected deltas; zoom stays within bounds; rotation is applied about the documented anchor.
  - For GUI instruments, PB‑VRT/Snapshot tests are preferred for visual invariants.
- Tests must live close to the owning app:
  - Example: `FountainGUIDemoTests`, `PatchBayAppUITests`, `MPEPadAppTests`, `MVKRuntimeServerTests`.

## 6. Instrument Index and Linting

- The instrument index (`Tools/instruments.json`) lists each first‑class instrument with:
  - `appId`, `agentId`, `corpusId`, `spec`, and optional `runtimeAgentId`.
- A linter (`instrument-lint` in `FountainTooling`) checks:
  - Spec file exists and is listed in `Scripts/openapi/openapi-to-facts.sh`.
  - Facts document exists in FountainStore for the `agentId`.
  - (Future) Teatro prompt and facts segments exist for the `appId`.
- CI should run the linter (for example via `Scripts/instrument-lint.sh`) and block merges when the Instrument Checklist is not satisfied.

## 7. Explicit Non‑Instrument Surfaces

- Some surfaces are intentionally not instruments (e.g. internal debug panels, non‑interactive docs). For those:
  - Add a short note in the nearest `AGENTS.md` explaining that the target is **not** an instrument and does not require PE or MIDI wiring.
  - Do **not** list them in `Tools/instruments.json`.

Keeping instruments aligned with this checklist makes them discoverable, controllable, and testable across GUI, runtime, and MIDI 2.0, and prevents “GUI only” surfaces from slipping in where a full instrument is required.

