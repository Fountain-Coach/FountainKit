# MetalViewKit Realtime Runtime — Overview

We provide a local/sidecar HTTP API to drive MIDI 2.0 and timing workflows deterministically for apps built with MetalViewKit. The runtime is platform‑neutral, supports loopback instruments for tests, and exposes narrow, scriptable routes.

What
- Health: `GET /health` returns `{status:"ok", uptimeSec}`.
- MIDI events: `POST /v1/midi/events` accepts timestamped UMP packets and forwards them to a target instrument.
- Endpoints: `GET/POST /v1/midi/endpoints` lists/creates runtime endpoints; listing reflects live MVK loopback instruments.
- Future: clock control, audio backend, tracing and metrics (scoped in the spec).

Why
- Deterministic testing: narrow, versioned routes allow repeatable demos and CI without UI automation.
- Interop: scripts and tools can target instruments by displayName or instanceId without CoreMIDI.

How
- Run server: `swift run --package-path Packages/FountainApps metalviewkit-runtime-server` (default port 7777).
- Inject UMP:
  - By display name substring: `POST /v1/midi/events?targetDisplayName=QuietFrame`.
  - By instanceId: `POST /v1/midi/events?targetInstanceId=qf-1`.
- Smoke locally: `bash Scripts/ci/mvk-runtime-smoke.sh` (writes `.fountain/logs/mvk-runtime-smoke-*.json`).
- Config: `MVK_BRIDGE_TARGET` default for display name routing (fallback to “Canvas” when unset).

Examples
- Health: `curl -s http://127.0.0.1:7777/health`.
- Inject a CC event: `curl -s -X POST 'http://127.0.0.1:7777/v1/midi/events?targetDisplayName=QuietFrame' -H 'Content-Type: application/json' -d '{"events":[{"tNs":"0","packet":{"w0":1074266112,"w1":65535}}]}'`.
- List endpoints: `curl -s http://127.0.0.1:7777/v1/midi/endpoints`.

Where
- Spec (curated): `Packages/FountainSpecCuration/openapi/v1/metalviewkit-runtime.yml`.
- Server: `Packages/FountainApps/Sources/metalviewkit-runtime-server/*`.
- Smoke: `Scripts/ci/mvk-runtime-smoke.sh`.
- QuietFrame apps: `Packages/FountainApps/Sources/quietframe-sonify-app/*`, `Packages/FountainApps/Sources/quietframe-companion-app/*` (first referential apps).

Notes
- Live listing includes loopback MVK instruments with `id = instanceId` for targeting. QuietFrame Sonify prints its identity at boot (`displayName`, `instanceId`) to aid scripting.
- The runtime complements in‑app transport; it does not replace CoreMIDI usage where appropriate.

