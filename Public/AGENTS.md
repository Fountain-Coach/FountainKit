## Public — Agent Guide (Publishing Frontend)

The `Public/` area hosts the publishing frontend for FountainAI: static docs/assets and small web apps that mirror core UIs for demos and documentation. It is Xcode‑independent and consumes OpenAPI surfaces from services in `Packages/`.

What
- Static pages and assets: `index.html`, `styles.css`, `reports/**`, `Audio/**`, `Models/**`.
- Web apps (TS/Node toolchain): `baseline-patchbay-web` — a grid‑only mirror of Baseline‑PatchBay.
- Launchers live under `Scripts/apps/` and are listed in that area’s AGENTS.

Why
- Provide a portable, deterministic frontend for publishing, demos, and future Playwright snapshot tests without requiring the macOS app runtime.

How
- Start PatchBay (backend): `swift run --package-path Packages/FountainApps patchbay-service-server` (defaults to `http://127.0.0.1:7090`).
- Launch web mirror: `Scripts/apps/baseline-patchbay-web` (seeds prompts, installs deps, starts Vite).
- Manual run (inside app folder): `PATCHBAY_URL=http://127.0.0.1:7090 npm run dev`.
- Build for static export: `npm run build` in the app folder (outputs to `dist/`).

Conventions
- OpenAPI‑first: use curated specs in `Packages/FountainSpecCuration/openapi/**` via the service route layer.
- No secrets in `Public/`; configure servers via env (e.g., `PATCHBAY_URL`) and Keychain on the service side.
- Proxies only: frontends call services through Vite dev proxies or absolute URLs; do not embed credentials.
- Do not commit generated OpenAPI clients or build artifacts unless explicitly required for hosting.

Where
- Web app: `Public/baseline-patchbay-web/**` (see its `AGENTS.md`).
- Launcher: `Scripts/apps/baseline-patchbay-web`.
- PatchBay spec: `Packages/FountainApps/Sources/patchbay-service/openapi.yaml` (source of truth curated at `Packages/FountainSpecCuration/openapi/v1/patchbay.yml`).

