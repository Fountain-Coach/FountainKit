# FountainAI MIDI Transport — Status and Design

We treat every interactive surface as a MIDI 2.0 instrument. Rendering remains transport‑agnostic; “instrument mode” is additive and optional. This document clarifies how transports are layered today and what callers can rely on.

What
- Loopback transport (in‑process): `LoopbackMetalInstrumentTransport` is the canonical test/robot path. It registers per‑instrument sessions in‑process and delivers UMP synchronously. Used by E2E tests and the MVK runtime smoke (`mvk-runtime-tests`).
- CoreMIDI transport (virtual endpoints): `CoreMIDIMetalInstrumentTransport` creates per‑view virtual endpoints (MIDI 2.0) on macOS, exposing a destination (receive) and a source (telemetry). Discovery and PE flow over SysEx7 UMP. Apps can target by endpoint display name.
- System transport (RTP fixed port): `MIDI2SystemInstrumentTransport(backend: .rtpFixedPort(5868))` provides a portable path when CoreMIDI is not desired. QuietFrame apps use this for deterministic pairing in local demos.
- Vendor JSON over SysEx7 UMP: For non‑PE commands we send a small vendor JSON payload under manufacturer 0x7D (dev) (`F0 7D 'JSON' 00 <utf8> F7`). Migration path is to full PE profiles.

Why
- Determinism: Loopback guarantees no external I/O variance for robots and CI. RTP fixed port keeps demos targetable. CoreMIDI remains available for operator workflows and external tools.
- Transport‑agnostic rendering: `MetalViewKit` renderers do not know about MIDI; transports are pluggable and confined to `MetalInstrument`.

How
- Enable instrument mode: construct `MetalInstrument` with a `MetalInstrumentDescriptor` (manufacturer, product, instanceId, displayName) and call `enable()`. Provide `stateProvider` to publish property snapshots on PE GET/notify.
- Pick a transport:
  - Robot/CI: `MetalInstrument.setTransportOverride(LoopbackMetalInstrumentTransport.shared)` (implicitly selected in ROBOT_ONLY mode).
  - macOS endpoints: `CoreMIDIMetalInstrumentTransport.shared`.
  - RTP fixed port: `MIDI2SystemInstrumentTransport(backend: .rtpFixedPort(5868))`.
- Identity and discovery: we reply to MIDI‑CI Discovery with manufacturer 0x7D and basic PE capabilities. Property Exchange uses JSON encoding for GET/SET/notify.

Where
- Code: `Packages/FountainApps/Sources/MetalViewKit/*` (instrument, transports, SysEx7 helpers).
- Runtime: `Packages/FountainApps/Sources/metalviewkit-runtime-server/*` (HTTP sidecar for UMP injection and inspection).
- Smoke: `Scripts/ci/mvk-runtime-smoke.sh` (runs `mvk-runtime-tests`).

Notes
- Display names: prefer stable names like `QuietFrame#qf-1`. Instance IDs are GUID‑like and map to MUID (28‑bit) for CI envelopes.
- Scheduling: UMP injections are timestamp‑normalized by receivers; JR timestamps are supported in transports and will be exercised in tests as we expand the runtime.

