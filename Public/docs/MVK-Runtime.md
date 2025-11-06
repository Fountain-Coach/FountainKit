# MetalViewKit Realtime Runtime — Overview

We provide a local/sidecar HTTP API to drive MIDI 2.0 and timing workflows deterministically for apps built with MetalViewKit. The runtime is platform‑neutral, supports loopback instruments for tests, and exposes narrow, scriptable routes.

What
- Health: `GET /health` returns `{status:"ok", uptimeSec}`.
- Clock: `GET /v1/clock`, `POST /v1/clock/test/enable`, `POST /v1/clock/test/advance` for deterministic time.
- MIDI IO: `POST /v1/midi/events` accepts timestamped UMP packets. `GET /v1/midi/vendor` reads back recorded events.
- Endpoints: `GET/POST /v1/midi/endpoints` (headless mode returns in‑memory endpoints; live MVK reflection is available when running in‑process with UI).
- Tracing & Metrics: `GET /v1/tracing/dump`, `GET /v1/metrics`.
- Audio (headless adapter): backend status, open/start/stop, and simple offline render (`POST /v1/audio/render`).

Why
- Deterministic testing: narrow, versioned routes allow repeatable demos and CI without UI automation.
- Interop: scripts and tools can target instruments by displayName or instanceId without CoreMIDI.

How
- Run server: `swift run --package-path Packages/FountainApps metalviewkit-runtime-server` (default port 7777).
- Inject UMP: `POST /v1/midi/events` with UMP packet words; read back via `GET /v1/midi/vendor` (use `limit`/`sinceNs`).
- Smoke locally: `bash Scripts/ci/mvk-runtime-smoke.sh` (JSON summary) or `bash Scripts/ci/mvk-runtime-probe.sh` (direct probes).
- Config: `MVK_RUNTIME_PORT` or `PORT` to override port; `MVK_BRIDGE_TARGET` is reserved for in‑process UI forwarding.

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
- In headless mode, live MVK reflection and vendor forwarding are disabled; tests rely on the runtime ring buffer for echo.
- The runtime complements in‑app transport; it does not replace CoreMIDI usage where appropriate.
