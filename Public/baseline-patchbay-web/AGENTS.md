## Baseline‑PatchBay (Web) — Agent Guide

A small TypeScript web app (Vite + React) that mirrors the Baseline‑PatchBay three‑pane UI: left and right scroll panes with draggable gutters and a center canvas instrument. It supports anchor‑stable zoom, pan, reset, and basic DnD logging, and can be driven over MIDI 2.0 via the `midi-service` bridge.

What
- Layout: three vertical panes, 6‑pt gutters; minimum pane widths 160 px; left/right fractions adjustable via gutters.
- Center canvas: crisp grid with minor/major lines and doc axes (x=0/y=0).
- Interactions: Ctrl+wheel zoom (anchor‑stable), wheel/drag pan, reset; left/center/right DnD events logged.
- REST wiring to PatchBay: read `GET /canvas`, apply `POST /canvas/zoom` and `POST /canvas/pan` when in REST mode.
- MIDI 2.0 drive mode (default): send vendor JSON (`ui.panBy`, `ui.zoomAround`, `canvas.reset`) to the “PatchBay Canvas” instrument via `midi-service`.

Why
- Portable publishing frontend for docs/demos without requiring the macOS app runtime. Mirrors the same OpenAPI contract and MRTS over MIDI 2.0 to reduce drift.

How
- Start PatchBay service: `swift run --package-path Packages/FountainApps patchbay-service-server`.
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
  - `GET /ump/tail` (tail), `POST /ump/flush` (flush) — aliases `GET/POST /ump/events` supported
  - `GET /headless/list`, `POST /headless/register`, `POST /headless/unregister`

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
- Mirror numeric invariants from Baseline‑PatchBay (pane mins, gutters, grid spacing = minor×majorEvery×zoom; anchor‑stable zoom ≤ 1 px drift).
- Web MRTS uses MIDI 2.0 UMP (SysEx7 vendor JSON/PE) via midi‑service with the same Teatro/MRTS prompts and facts as Swift.

Roadmap
- Add TS OpenAPI client generation from curated specs.
- Add minimal PE SET encoder in TS (or server‑side helpers in `midi-service`).
- Optional Python mirror (FastAPI) alongside this app if needed for docs hosting.
- Web MRTS runners:
  - Headless canvas parity: `npm run mrts:run && npm run mrts:assert` with `TARGET_NAME="Headless Canvas"`.
  - Editor flow (after wiring): set `TARGET_NAME="Fountain Editor"` and run an editor‑specific script.
