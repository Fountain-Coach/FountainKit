## Baseline‑PatchBay (Web) — Agent Guide

A small TypeScript web app (Vite + React) that mirrors the Baseline‑PatchBay grid‑only UI. It renders a crisp grid canvas and supports anchor‑stable zoom, pan, and reset, mirroring operations to the PatchBay service.

What
- Canvas grid with minor/major lines and doc axes (x=0/y=0).
- Interactions: Ctrl+wheel zoom (anchor‑stable), wheel pan, reset.
- REST wiring to PatchBay: read `CanvasState`, apply `zoom` and `pan`.

Why
- Portable publishing frontend for docs/demos without requiring the macOS app runtime. Mirrors the same OpenAPI contract and MRTS over MIDI 2.0 to reduce drift.

How
- Start PatchBay: `swift run --package-path Packages/FountainApps patchbay-service-server`.
- Start MIDI bridge: `Scripts/apps/midi-service` (or `swift run --package-path Packages/FountainApps midi-service-server`).
- Seed prompts (optional): `npm run seed` (runs `grid-dev-seed` + `baseline-robot-seed`).
- Dev server: `PATCHBAY_URL=http://127.0.0.1:7090 MIDI_SERVICE_URL=http://127.0.0.1:7180 npm run dev` (or `Scripts/apps/baseline-patchbay-web`).
- Build static: `npm run build` (emits `dist/`).
- Proxy: Vite dev proxy rewrites `/api/patchbay/*` → `PATCHBAY_URL`, `/api/midi/*` → `MIDI_SERVICE_URL`.

Routes used
- PatchBay (REST): `GET /canvas`, `POST /canvas/zoom`, `POST /canvas/pan`.
- MIDI service (OpenAPI):
  - `GET /endpoints` (list destinations)
  - `POST /ump/send` (deliver UMP to `target.displayName`)
  - `GET /ump/events` (tail recorder events), `POST /ump/events` (flush)
  - `GET /headless/instruments`, `POST /headless/instruments`, `DELETE /headless/instruments/{displayName}`

Where
- App shell: `Public/baseline-patchbay-web/index.html`.
- Entry: `Public/baseline-patchbay-web/src/main.tsx`.
- UI: `Public/baseline-patchbay-web/src/ui/App.tsx`, `Public/baseline-patchbay-web/src/ui/Grid.ts`.
- REST client: `Public/baseline-patchbay-web/src/ws/patchbay.ts`.
- Dev config: `Public/baseline-patchbay-web/vite.config.ts`.
- Launcher: `Scripts/apps/baseline-patchbay-web`.
- Web MRTS helpers: `Public/baseline-patchbay-web/src/midi2/*` and `Public/baseline-patchbay-web/scripts/mrts-*.js`.
- Spec: `Packages/FountainApps/Sources/patchbay-service/openapi.yaml` (curated at `Packages/FountainSpecCuration/openapi/v1/patchbay.yml`).
- MIDI bridge spec/server: `Packages/FountainSpecCuration/openapi/v1/midi-service.yml`, `Packages/FountainServiceKit-MIDI/Sources/MIDIService/*`.

Conventions
- OpenAPI‑first; do not hand‑edit generated clients if added later.
- No secrets or `.env` committed; pick up `PATCHBAY_URL` and `MIDI_SERVICE_URL` from env.
- Mirror numeric invariants from Baseline‑PatchBay (grid spacing = minor×majorEvery×zoom; anchor‑stable zoom ≤ 1 px drift).
- Web MRTS uses MIDI 2.0 UMP (SysEx7 vendor JSON, and later MIDI‑CI PE) sent via the MIDI service; same prompts and facts as Swift tests.

Roadmap
- Add TS OpenAPI client generation from curated specs.
- Add minimal PE SET encoder in TS (or server‑side helpers in `midi-service`).
- Optional Python mirror (FastAPI) alongside this app if needed for docs hosting.
 - Web MRTS runner is available: `npm run mrts:run` (reads `store-dump` facts, sends UMP to PatchBay Canvas via midi-service).
