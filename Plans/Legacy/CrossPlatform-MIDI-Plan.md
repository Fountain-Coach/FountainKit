## Cross-Platform MIDI Independence Plan

### Context — Why Change
PatchBay still calls CoreMIDI directly when enabling instruments (`Packages/FountainApps/Sources/patchbay-app/Canvas/MetalCanvasHost.swift:206`). If `midiserver` crashes, the UI thread blocks inside `MetalInstrument.enable()` while waiting on `MIDIDestinationCreateInternal`. We already own a complete MIDI 2.0 stack (`Packages/FountainTelemetryKit/Sources/MIDI2*`) and robot harnesses that can drive PatchBay without CoreMIDI, so it is time to remove the daemon as a hard dependency and deliver a portable transport layer that works on macOS, Linux, and CI.

### Goals
1. Make PatchBay resilient: no hangs when CoreMIDI is unavailable; surface health in the UI.
2. Deliver a MIDI transport abstraction that defaults to our MIDI 2.0 implementation and runs cross-platform.
3. Introduce a bridge service that can proxy to CoreMIDI when legacy drivers demand it, but keep the app decoupled.
4. Prepare for fully native drivers (USB, BLE, RTP) so we can run without CoreMIDI entirely.

### Phase 1 — Transport Abstraction (PatchBay)
- Add a `MIDITransportProvider` protocol around the existing CoreMIDI calls in `MetalCanvasHost`, `StageInstrumentsBinder`, and `MetalInstrument`.
- Provide two implementations:
  - `CoreMIDITransportProvider` (compatibility path; current behavior behind an abstraction).
  - `MIDI2TransportProvider` that uses `Packages/FountainTelemetryKit/Sources/MIDI2Transports` for UMP routing (shared memory/loopback).
- Inject the provider through `AppState` so robot tests can run both paths; update `Packages/FountainApps/Tests/PatchBayAppUITests` to cover the matrix.
- Add non-blocking enable logic: create endpoints asynchronously with a timeout and surface failures through `AppState` warnings.

### Phase 2 — MIDI Bridge Service
- Create `Packages/FountainServiceKit-MIDI` with:
  - A Swift server that exposes health, device enumeration, endpoint management, and property exchange over HTTP (driven by a new `openapi/v1/midi-service.yaml` spec under `Packages/FountainSpecCuration/openapi`).
  - A transport core that uses our MIDI 2.0 stack.
  - An optional CoreMIDI adapter module for macOS that instantiates endpoints via CoreMIDI but presents them through the service.
- Update PatchBay to consume the service using generated clients (`FountainGatewayKit` integration), so the app only ever talks to the service—CoreMIDI lives behind the boundary.
- Extend `Scripts/dev/` to include `midi-health` and bridge management helpers; wire CI smoke tests to verify the service responds.

### Phase 3 — Hardware Access Without CoreMIDI
- Implement or adopt user-space drivers for common transports:
  - USB MIDI class → UMP conversion (libusb + MIDI 2.0 codec).
  - BLE MIDI via CoreBluetooth (macOS/iOS) and equivalent libraries on Linux.
  - RTP-MIDI already handled by existing transports.
- Plug these drivers into the bridge service as pluggable adapters. CoreMIDI remains only as a fall-back adapter for machines that still need it.

### Phase 4 — Rollout & Observability
- Default PatchBay to the MIDI 2.0 provider; leave CoreMIDI behind a feature flag for legacy troubleshooting.
- Expand robot tests and CI to run against both the pure MIDI 2.0 path and the CoreMIDI bridge path until confidence is high.
- Instrument the bridge and PatchBay with telemetry (latency, dropped packets, daemon crashes) via `FountainTelemetryKit`.
- Document operator workflows in `Scripts/AGENTS.md` and PatchBay service AGENTS files (health badges, recovery steps, toggling providers).

### Robot Testing Alignment
- Robot harnesses (`Packages/FountainApps/Tests/PatchBayAppUITests/*Robot*.swift`) become the canonical acceptance suite for the transport swap. Each phase must keep snapshots, MIDI UMP expectations, and service assertions in sync.
- Integrate the improvements outlined in `Plans/Legacy/Robot-Testing.md`:
  - Add temporal assertions so transport swaps do not regress time-based behaviours (RobotTimeline + MIDI ramps).
  - Capture hit-testing metrics when the new transport is active to ensure precision across platforms.
  - Extend the DSL toward agent-style capabilities (latency, phase lock) that exercise the service health endpoints introduced in Phase 2.
  - Version golden artefacts via FountainStore as part of the new transport rollout; drift detection becomes a gating signal.
- Update CI to publish structured robot reports (JSON) so transport regressions surface in the same telemetry channel as the bridge service.

### Next Actions
1. Draft the transport abstraction RFC and prototype (`Phase 1`) so PatchBay can load either provider without invasive changes.
2. Define the `midi-service` OpenAPI contract and align with service owners.
3. Schedule time with robot test maintainers to expand coverage for the dual-transport matrix.
