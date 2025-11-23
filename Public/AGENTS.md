## Public — Agent Guide (Publishing Frontend)

The `Public/` area hosts the publishing frontend for FountainAI: static docs/assets and small web apps that mirror core UIs for demos and documentation. It is Xcode‑independent and consumes OpenAPI surfaces from services in `Packages/`.

What
- Static pages and assets: `Public/index.html`, `Public/styles.css`, `Public/reports/**`, `Public/Audio/**`, `Public/Models/**`.
- Web apps (TS/Node): `Public/baseline-patchbay-web` — three‑pane Baseline‑PatchBay mirror (left/center/right panes, draggable gutters, DnD items); `Public/teatro-stage-web` — Teatro Stage Engine web host (room + puppet SVG view, legacy Cannon/Three stack under `src-legacy/**`).
- Runtime docs: `Public/docs/MVK-Runtime.md` (HTTP runtime overview) and `Public/docs/MIDI-Transport-Status.md` (transport status/choices).
- Launchers live under `Scripts/apps/` and are listed in that area’s AGENTS.

Why
- Provide a portable, deterministic frontend for publishing and demos without requiring the macOS app runtime.

Prompt‑first rule
- This web mirror follows the same Teatro prompt as the mac baseline. Always fetch the current Teatro prompt from FountainStore first; propose prompt edits; then implement; seed and print prompts on boot; keep facts in sync.

How
- Start PatchBay service (REST): `swift run --package-path Packages/FountainApps patchbay-service-server`.
- Start MIDI service (UMP bridge): `Scripts/apps/midi-service`.
  - Backends: `MIDI_SERVICE_BACKEND=coremidi|alsa|rtp|loopback` (macOS default coremidi; Linux default alsa).
  - Recorder: NDJSON logs to `.fountain/corpus/ump` (override `MIDI_UMP_LOG_DIR`).
- Launch web mirror: `Scripts/apps/baseline-patchbay-web` (seeds prompts, installs deps, starts Vite).
- Manual run (inside app folder): `PATCHBAY_URL=http://127.0.0.1:7090 MIDI_SERVICE_URL=http://127.0.0.1:7180 npm run dev`.
- Build for static export: `npm run build` in the app folder (outputs to `dist/`).
- MVK runtime smoke: `bash Scripts/ci/mvk-runtime-smoke.sh` (verifies health, loopback listing, and UMP forwarding; writes `.fountain/logs/mvk-runtime-smoke-*.json`).

Conventions
- OpenAPI‑first: use curated specs in `Packages/FountainSpecCuration/openapi/**` via the service route layer. MIDI service spec includes recorder + headless endpoints.
- MIDI 2.0 robot control: drive instruments by sending UMP (SysEx7) via midi‑service; reuse the same Teatro/MRTS prompts and numeric invariants as the Swift suite.
- No secrets in `Public/`; configure servers via env (e.g., `PATCHBAY_URL`, `MIDI_SERVICE_URL`) and Keychain on the service side.
- Proxies only: frontends call services through Vite dev proxies or absolute URLs; do not embed credentials.
- Do not commit generated OpenAPI clients or build artifacts unless explicitly required for hosting.

Where
- Web app: `Public/baseline-patchbay-web/**` (see `Public/baseline-patchbay-web/AGENTS.md`).
- Launcher: `Scripts/apps/baseline-patchbay-web`.
- PatchBay spec: `Packages/FountainApps/Sources/patchbay-service/openapi.yaml` (curated at `Packages/FountainSpecCuration/openapi/v1/patchbay.yml`).
- MIDI Service spec/server: `Packages/FountainSpecCuration/openapi/v1/midi-service.yml`, `Packages/FountainServiceKit-MIDI/Sources/MIDIService/*`.
- MVK Runtime docs: `Public/docs/MVK-Runtime.md`; transport status: `Public/docs/MIDI-Transport-Status.md`.
- MVK Runtime spec/server: `Packages/FountainSpecCuration/openapi/v1/metalviewkit-runtime.yml`, `Packages/FountainApps/Sources/metalviewkit-runtime-server/*`.
