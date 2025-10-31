Baseline‑PatchBay (Web)

What
Mirror of the Baseline‑PatchBay UI in a small TypeScript web app (Vite + React). It renders the grid canvas, supports zoom/pan/reset, and mirrors operations to PatchBay’s REST API.

Why
Provide a publishing‑frontend view that is portable (no Xcode) and OpenAPI‑driven. Robot control mirrors the Swift MRTS via MIDI 2.0 messages sent over the MIDI service bridge.

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

Web MRTS (MIDI 2.0)
- Start MIDI bridge: `swift run --package-path Packages/FountainApps midi-service-server` (default `http://127.0.0.1:7180`).
- Send vendor JSON ops (examples):
  - Reset: `MIDI_SERVICE_URL=http://127.0.0.1:7180 TARGET_NAME="PatchBay Canvas" npm run mrts:reset`
  - Pan: `DX=120 DY=80 npm run mrts:pan`
  - Zoom: `AX=512 AY=384 MAG=0.2 npm run mrts:zoom`
- Under the hood: scripts use `src/midi2/*` to build SysEx7 UMP and post to `midi-service` `/ump/send`.

MRTS runner
- One‑shot sequence (reset → pan → zoom): `MIDI_SERVICE_URL=http://127.0.0.1:7180 TARGET_NAME="PatchBay Canvas" npm run mrts:run`
- Reads MRTS facts via `store-dump` (Teatro/MRTS seeded segments) when available.
 - Numeric invariants: `npm run mrts:assert` (asserts follow‑finger pan and anchor‑stable zoom via CI notify snapshots; eps defaults to 1.0 px).

Notes
- Reset via REST is two calls; with MIDI 2.0 you can also emit the vendor JSON `canvas.reset`.
- TS OpenAPI client generation can be added later via `openapi-typescript-codegen` using curated specs as source of truth.
