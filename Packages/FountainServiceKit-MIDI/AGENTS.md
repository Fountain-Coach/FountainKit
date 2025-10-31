## MIDI Service — Agent Guide

Cross‑platform MIDI 2.0 bridge for instruments and PatchBay. Provides health, transport enumeration, endpoint lifecycle, and UMP send over HTTP. Backed by FountainTelemetryKit transports (CoreMIDI on macOS; loopback/ALSAbased placeholders elsewhere).

What
- Server: `midi-service-server` (HTTP on `MIDI_SERVICE_PORT`/`PORT`, default 7180).
- Routes (curated at `Packages/FountainSpecCuration/openapi/v1/midi-service.yml`):
  - `GET /health`, `GET /transports`, `GET /devices`.
  - `GET /endpoints` — list visible CoreMIDI destinations (name only).
  - `POST /endpoints` (stub) — create managed endpoints.
  - `POST /ump/send { target.displayName, words[] }` — send UMP to a destination.

How
- Build/run: `swift run --package-path Packages/FountainApps midi-service-server`.
- Send UMP (example): POST to `/ump/send` with `words` as uint32 array (SysEx7 UMP, note/CC, etc.).
- Browser bridge: the web MRST helpers in `Public/baseline-patchbay-web/src/midi2/*` encode vendor JSON/PE to UMP and POST here.

Notes
- `sendUMP` uses CoreMIDI when available; it looks up or creates a per‑destination sender and keeps it open.
- This service doesn’t interpret UMP; instruments do. Vendor JSON topics like `ui.panBy`/`ui.zoomAround` and MIDI‑CI PE SET are interpreted by the macOS app’s instruments.

