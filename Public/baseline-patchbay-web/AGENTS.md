## Baseline‑PatchBay (Web) — Agent Guide

A small TypeScript web app (Vite + React) that mirrors the Baseline‑PatchBay grid‑only UI. It renders a crisp grid canvas and supports anchor‑stable zoom, pan, and reset, mirroring operations to the PatchBay service.

What
- Canvas grid with minor/major lines and doc axes (x=0/y=0).
- Interactions: Ctrl+wheel zoom (anchor‑stable), wheel pan, reset.
- REST wiring to PatchBay: read `CanvasState`, apply `zoom` and `pan`.

Why
- Portable publishing frontend for docs/demos and future Playwright snapshot tests without requiring the macOS app runtime. Follows the same OpenAPI contract as the Swift app to reduce drift.

How
- Start backend: `swift run --package-path Packages/FountainApps patchbay-service-server`.
- Seed prompts (optional): `npm run seed` (runs `grid-dev-seed` + `baseline-robot-seed`).
- Dev server: `PATCHBAY_URL=http://127.0.0.1:7090 npm run dev` (or `Scripts/apps/baseline-patchbay-web`).
- Build static: `npm run build` (emits `dist/`).
- Proxy: Vite dev proxy rewrites `/api/patchbay/*` → `PATCHBAY_URL`.

Routes used
- `GET /canvas` → initial `CanvasState { transform: { scale, translation }, gridStep }`.
- `POST /canvas/zoom { scale, anchorView? }`.
- `POST /canvas/pan { dx, dy }` (doc‑space deltas).

Where
- App shell: `Public/baseline-patchbay-web/index.html`.
- Entry: `Public/baseline-patchbay-web/src/main.tsx`.
- UI: `Public/baseline-patchbay-web/src/ui/App.tsx`, `Public/baseline-patchbay-web/src/ui/Grid.ts`.
- REST client: `Public/baseline-patchbay-web/src/ws/patchbay.ts`.
- Dev config: `Public/baseline-patchbay-web/vite.config.ts`.
- Launcher: `Scripts/apps/baseline-patchbay-web`.
- Spec: `Packages/FountainApps/Sources/patchbay-service/openapi.yaml` (curated at `Packages/FountainSpecCuration/openapi/v1/patchbay.yml`).

Conventions
- OpenAPI‑first; do not hand‑edit generated clients if added later.
- No secrets or `.env` committed; pick up `PATCHBAY_URL` from the environment.
- Mirror numeric invariants from Baseline‑PatchBay (grid spacing = minor×majorEvery×zoom; anchor‑stable zoom ≤ 1 px drift).

Roadmap
- Add TS OpenAPI client generation from the curated spec.
- Add Playwright snapshot tests at 1440×900 and 1280×800.
- Optional Python mirror (FastAPI) alongside this app if needed for docs hosting.

