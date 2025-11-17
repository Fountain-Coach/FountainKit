# AGENT — Scripts/apps (app launchers & packaging)

Scope: `Scripts/apps/**`.

Purpose
- Keep app launchers and packaging scripts together (Studio, Engraver, MemChat, etc.).
- Provide stable shims from legacy paths under `Scripts/`.

Included scripts (canonical)
- `launch-composer-studio.sh` — Launch the new Composer Studio app.
- `launch-audiotalk-studio.sh` — Legacy Studio (deprecated; use `--force-legacy`).
- `launch-engraver-studio-app.sh` — Launch Engraver Studio app.
- `launch-memchat-app.sh` — Launch MemChat app.
- `memchat-oneclick.sh` — One‑click MemChat starter for dev.
- `baseline-patchbay-web` — Seeds Teatro prompts and launches the web mirror (Vite) of Baseline‑PatchBay.
- `midi-service` — Launch the MIDI 2.0 HTTP bridge (`/ump/send`) for web MRTS.
- `mpe-pad-app` — One‑click SwiftUI app for the MPE Pad instrument. Transports: BLE Peripheral, BLE Central, RTP (MIDI 2.0), and CoreMIDI sidecar (MIDI 1.0 over HTTP).
- `mpe-pad-host` — Seeds facts for the `mpe-pad` agent and starts the headless MIDI 2.0 host with MPE handlers.
- `midi-bridge` — Starts/stops the external CoreMIDI sidecar (AudioKit lane). Requires `BRIDGE_CMD` to point to the sidecar binary; optional `BRIDGE_PORT`, `BRIDGE_NAME`.
- `quietframe-runtime` — Launch QuietFrame Sonify wired to the MVK runtime (Loopback transport). Sets `QF_USE_RUNTIME=1` and `MVK_BRIDGE_TARGET` (default `QuietFrame#qf-1`).
- `quietframe-stack` — One‑button dev stack: starts the MVK runtime sidecar and QuietFrame Sonify (instrument). Supports `up|down|status`.

Conventions
- Keep the UX/config minimal; all environment and secrets managed via Keychain or defaults.
- If a launcher must be deprecated, print a clear message and exit unless forced.

Sidecar (CoreMIDI) usage
- We keep FountainKit CoreMIDI‑free. For hosts that only accept MIDI 1.0 (AUM, DAWs), use the separate sidecar:
  - Build/run the sidecar (see `Sidecar/FountainCoreMIDIBridge/README.md`), or point `BRIDGE_CMD` to a prebuilt binary.
  - Start it: `BRIDGE_CMD=/abs/path/to/FountainCoreMIDIBridge Scripts/apps/midi-bridge start`.
  - In `mpe-pad-app`, switch transport to “Sidecar”; messages are reduced to MIDI 1.0 and POSTed to `/midi1/send` on the sidecar.
  - RTP session (no Audio MIDI Setup): enable with `curl -s -X POST -H 'Content-Type: application/json' localhost:${BRIDGE_PORT:-18090}/rtp/session -d '{"enable":true}'`; optional connect: `curl -s -X POST -H 'Content-Type: application/json' localhost:${BRIDGE_PORT:-18090}/rtp/connect -d '{"host":"127.0.0.1","port":5004}'`.
  - BLE Peripheral advertising (experimental): `curl -s -X POST -H 'Content-Type: application/json' localhost:${BRIDGE_PORT:-18090}/ble/advertise -d '{"enable":true, "name":"MPE Pad"}'`; status: `curl -s localhost:${BRIDGE_PORT:-18090}/ble/status`.
