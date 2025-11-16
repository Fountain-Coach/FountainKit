## MetalViewKit Runtime — Generic Instrument State Plan

### Context — Why This Extension

MetalViewKit already has a shared runtime (`metalviewkit-runtime-server`) that exposes clock, MIDI, audio, tracing, and test hooks over HTTP, and a shared MIDI instruments host (`midi-instrument-host`) that loads OpenAPI-derived facts and exposes properties as MIDI‑CI PE. Today, instrument-specific properties (like canvas zoom/translation/rotation) are either served by separate app services or not exposed as HTTP at all. The FountainGUIKit demo now has a spec and facts (`fountain-gui-demo.yml` → `fountain.coach/agent/fountain-gui-demo/service`), but no runtime endpoint that owns its state.

We want the runtime to offer a **generic, spec-backed instrument state surface** so multiple GUI instruments (including the demo) can share a single runtime and MIDI host, without adding a per-instrument server.

### Goals

- Keep `metalviewkit-runtime` **instrument-agnostic**: it must not know about specific apps or view types.
- Introduce a **generic “instrument state” API** in the runtime spec that can:
  - store and return property maps for arbitrary instrument ids, and
  - be targeted by facts from any agent (including the FountainGUIKit demo).
- Integrate with the existing facts → MIDI host pipeline so CI/PE SET/GET calls can map into the runtime instrument state operations.
- Ensure all changes are Swift 6 concurrency-safe and covered by tests (`mvk-runtime-tests`).

### Phase 1 — Inventory and Requirements

- Catalogue existing runtime capabilities:
  - `MetalViewKitRuntimeServerKit/openapi.yaml` (clock, MIDI, audio, tracing).
  - `MVKRuntimeCore` and `MVKRuntimeHandlers` (session, clock, MIDI event store, metrics).
  - `mvk-runtime-tests` (current health + MIDI echo checks).
- Confirm design constraints from AGENTS:
  - Runtime stays transport-agnostic and instrument-neutral.
  - No CoreMIDI; MIDI2 only via RTP/loopback.
  - No hard references to app-specific views or state types.
- Identify consumers:
  - FountainGUIKit demo (`fountain-gui-demo-app`).
  - PatchBay/Canvas, future MetalViewKit instruments.

### Phase 2 — Spec Design (Instrument State in metalviewkit-runtime)

- Extend `Packages/FountainApps/Sources/MetalViewKitRuntimeServerKit/openapi.yaml` to add generic instrument state endpoints:
  - `GET /v1/instruments/{id}/state`
    - `operationId: getInstrumentState`
    - Path parameter `{id}` is a string instrument id (agent id or instance id).
    - Returns a generic property map:
      - e.g. `{ "properties": { "name": "value", ... } }` or a `InstrumentState` schema with `additionalProperties: { type: number|string|boolean }`.
  - `POST /v1/instruments/{id}/state`
    - `operationId: setInstrumentState`
    - Accepts a body with partial or full property map.
    - Applies updates and returns 204 or the updated state.
- Keep the schema generic:
  - Do not bake in `canvas.*` names; instead, model a map `{ [propertyName: string]: JSON value }`.
  - Allow numeric and boolean primitives so facts can map PE properties to appropriate JSON types.
- Update runtime summary/description in the spec to mention “generic instrument state for GUI and audio instruments”.
- Regenerate server code via `swift build` with the OpenAPI plugin, ensuring no manual edits under `MetalViewKitRuntimeServerKit` conflict with generated files.

### Phase 3 — Runtime Core Implementation

- Extend `MVKRuntimeCore` with a generic instrument state store:
  - Add `var instruments: [String: [String: Any]] = [:]` keyed by instrument id (`agentId` or instance id).
  - Provide helpers:
    - `func getInstrumentState(id: String) -> [String: Any]`
    - `func applyInstrumentPatch(id: String, patch: [String: Any])`
  - Ensure access is concurrency-safe:
    - Either keep `MVKRuntimeCore` single-threaded behind the NIO event loop, or introduce an actor wrapper if we need cross-thread safety.
- Implement the new handlers in `MVKRuntimeHandlers`:
  - `getInstrumentState`:
    - Reads state from `core.instruments[id]` or returns an empty map.
    - Wraps it into the OpenAPI `InstrumentState` response type.
  - `setInstrumentState`:
    - Decodes the incoming JSON map into `[String: Any]`.
    - Calls `core.applyInstrumentPatch`.
    - Optionally records a `TraceEvent` (`instrument.state.set`) for observability.
- Keep the implementation generic; do **not** interpret specific property names or ranges in the runtime.

### Phase 4 — Facts and MIDI Host Integration

- Decide agent routing for instrument state:
  - For GUI-only instruments (like the FountainGUIKit demo), plan to route PE properties to `metalviewkit-runtime`’s new `/v1/instruments/{id}/state` endpoints instead of app-specific services.
- Extend the facts generator config (`openapi-to-facts`) if needed:
  - Ensure that, for agents that opt in, property routes map to:
    - `GET /v1/instruments/{id}/state` for PE GET.
    - `POST /v1/instruments/{id}/state` for PE SET.
  - Use the existing `mapsTo.openapi` mechanism so `midi-instrument-host` does not need special cases.
- In `midi-instrument-host.buildPropertyRoutes`:
  - No special changes should be necessary if facts carry the correct `path`/`method` for the runtime endpoints.
  - Verify that setting `AGENT_BASE_URL_FOUNTAIN_COACH_AGENT_FOUNTAIN_GUI_DEMO_SERVICE` (or a generic `AGENT_BASE_URL`) to the `metalviewkit-runtime` URL allows the host to reach these endpoints.

### Phase 5 — Demo/App Wiring (FountainGUIKit Demo)

- Keep the demo app decoupled from the runtime:
  - The app continues to map FGK events → `canvas.*` properties via `FGKNode` and `FGKPropertyConsumer`.
  - It does not call the runtime directly.
- Use CI/PE + runtime to drive the demo in tests:
  - Configure `midi-instrument-host` with:
    - `HOST_AGENTS=fountain.coach/agent/fountain-gui-demo/service`
    - `AGENT_BASE_URL_FOUNTAIN_COACH_AGENT_FOUNTAIN_GUI_DEMO_SERVICE=http://127.0.0.1:<mvk-runtime-port>`
  - Robot/MRTS tests send MIDI‑CI PE SET for `canvas.*` to the host, which:
    - translates them to HTTP `POST /v1/instruments/{id}/state`,
    - updates the runtime store for that instrument.
  - The demo app, in turn, can poll or subscribe to instrument state via its own mechanisms (future work), or continue to apply properties on the main actor, with the runtime used as the canonical external surface.

### Phase 6 — Testing and Validation

- Extend `mvk-runtime-tests` to cover the new instrument state endpoints:
  - Start `metalviewkit-runtime-server` on an ephemeral port.
  - `POST /v1/instruments/demo/state` with a small state map (e.g. zoom/translation).
  - `GET /v1/instruments/demo/state` and verify the map matches.
- Add a focused integration test that:
  - Seeds facts for `fountain-gui-demo`.
  - Starts `metalviewkit-runtime-server` and `midi-instrument-host` with `HOST_AGENTS` including the demo.
  - Sends a PE SET over MIDI to the demo instrument via the host and asserts that the runtime’s `/v1/instruments/{id}/state` reflects the change.
- Keep all new code Swift 6 concurrency-clean:
  - Avoid global mutable state outside the runtime core.
  - If actors are introduced in the runtime, document their threading model in a short AGENTS note under `MetalViewKitRuntimeServerKit`.

### Phase 7 — Documentation and Adoption

- Update `Packages/FountainApps/Sources/MetalViewKit/AGENTS.md` (and/or add a small AGENTS file under `MetalViewKitRuntimeServerKit`) to describe:
  - The new generic instrument state endpoints.
  - How facts and `midi-instrument-host` interact with them.
  - How GUI instruments (including the FountainGUIKit demo) can opt in by targeting `metalviewkit-runtime` in their OpenAPI/facts.
- Ensure the root `AGENTS.md` Plans Index points to this plan so future work on MetalViewKit runtime follows the same path.

