Baseline‑PatchBay (Web)

What
Mirror of the Baseline‑PatchBay UI in a small TypeScript web app (Vite + React). It renders the grid canvas, supports zoom/pan/reset, and mirrors operations to PatchBay’s REST API.

Why
Provide a publishing‑frontend view that is portable (no Xcode), OpenAPI‑driven, and suitable for docs/demos and Playwright snapshot tests.

How
- Start PatchBay: `swift run --package-path Packages/FountainApps patchbay-service-server` (default http://127.0.0.1:7090)
- Seed prompts (optional): `npm run seed` inside this folder
- Run web app: `PATCHBAY_URL=http://127.0.0.1:7090 npm run dev`
- One‑liner: `Scripts/apps/baseline-patchbay-web`

Routes used
- `GET /canvas` → initial `CanvasState`
- `POST /canvas/zoom { scale, anchorView? }` → zoom (anchor‑stable)
- `POST /canvas/pan { dx, dy }` → pan by doc‑space delta

Where
- App entry: `Public/baseline-patchbay-web/src/ui/App.tsx`
- Grid painter: `Public/baseline-patchbay-web/src/ui/Grid.ts`
- API client: `Public/baseline-patchbay-web/src/ws/patchbay.ts`
- Dev config: `Public/baseline-patchbay-web/vite.config.ts`
- Launcher: `Scripts/apps/baseline-patchbay-web`

Notes
- Reset uses `GET /canvas` + `POST /canvas/pan` (−translation) + `POST /canvas/zoom {scale:1}`.
- OpenAPI client generation can be added later via `openapi-typescript-codegen` using `Packages/FountainSpecCuration/openapi/v1/patchbay.yml` as the source of truth.

