# FountainApps

Executable entry points for FountainKit (servers, CLIs, UIs). This package stitches together the service kits and core runtime.

## Fast Local Servers

- One‑shot convenience: `Scripts/dev-servers-up.sh` prebuilds required server binaries and starts them with readiness checks.
  - Flags: `--no-extras` (core only), `--release` (build/run release configuration)
- Manual prebuild: `bash Scripts/dev-up prebuild --all` (or set `DEV_UP_CONFIGURATION=release`).
- Start with checks: `DEV_UP_USE_BIN=1 DEV_UP_CHECKS=1 bash Scripts/dev-up --all`.
- Logs/PIDs: `.fountain/logs`, `.fountain/pids`

Core services and readiness (localhost):
- baseline-awareness: `8001` — `GET /metrics`
- bootstrap: `8002` — `GET /metrics`
- planner: `8003` — `GET /metrics`
- function-caller: `8004` — `GET /metrics`
- persist: `8005` — `GET /metrics`
- gateway: `8010` — `GET /metrics` (JSON)
- audiotalk: `8080` — `GET /audiotalk/meta/health`

Extras (with `--all`):
- tools-factory: `8011` — `GET /metrics`
- tool-server: `8012` — `GET /_health` (200)
- semantic-browser: `8007` — `GET /metrics`
 - audiotalk-cli: `swift run --package-path Packages/FountainApps audiotalk-cli --help`

## MemChat App

- Launch: `bash Scripts/launch-memchat-app.sh`
- Requires `OPENAI_API_KEY` in Keychain (service: `FountainAI`, account: `OPENAI_API_KEY`). The launcher fails fast if missing.
- Uses on‑disk FountainStore by default; override with `ENGRAVER_STORE_PATH`.

## Individual Services (ad‑hoc)

Run a single executable directly from this package:
- `swift run --package-path Packages/FountainApps gateway-server`
- `swift run --package-path Packages/FountainApps baseline-awareness-server`
- `swift run --package-path Packages/FountainApps audiotalk-server`
- Replace the product name to target other executables.

Helpers:
- `Scripts/run-audiotalk.sh` starts `audiotalk-server` with a default `LAUNCHER_SIGNATURE` and logs to `~/.fountain/audiotalk.log`.

Refer to the workspace README for the full service map and development workflow.
