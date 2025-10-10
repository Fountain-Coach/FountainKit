# FountainKit Onboarding

This guide helps you run FountainKit locally in minutes without learning every package first.

## Quick Start

- Build the entire workspace (one graph):
  - `swift build`
- Start the LocalAgent (mock fallback if it can’t start):
  - `Scripts/launcher start` (logs: `.fountain/logs/launcher.log`)
- Export the launcher signature and start the core services in the background:
  - `Scripts/dev-up` (prefers prebuilt binaries; builds once if needed)
  - Tip: to also export the signature into your current shell, run: `source Scripts/dev-up env`
- Optional: wait for readiness probes and JSON metrics
  - `Scripts/dev-up --check`
- Verify gateway is up:
  - `curl -s http://127.0.0.1:8010/metrics | head -n1`
- Exercise the gateway → LocalAgent path:
  - `curl -s -X POST 'http://127.0.0.1:8010/chat' -H 'Content-Type: application/json' -d '{"messages":[{"role":"user","content":"hello"}]}'`
- Stop everything:
  - `Scripts/dev-down`

## Check Status

- Inspect which services are up, which ports they listen on, and PIDs:
  - `Scripts/dev-status`
  - Output columns: `SERVICE`, `PORT`, `STATUS` (up/down), `PID` (if managed by dev-up)

## What Dev Scripts Do

- `Scripts/dev-up` starts core servers in the background with logs and pids under `.fountain/` and injects the required `LAUNCHER_SIGNATURE` for signed targets.
- `Scripts/dev-down` stops those background servers and the LocalAgent.
- `Scripts/dev-status` shows a quick overview of listeners and known PIDs.

Core services started by default:
- gateway-server (8010)
- bootstrap-server (8002)
- baseline-awareness-server (8001)
- planner-server (8003)
- function-caller-server (8004)
- persist-server (8005)

Optional extras with `--all`:
- semantic-browser-server (8007) — now lives in `Packages/FountainApps-SemanticBrowser`
- tools-factory-server (8011)
- tool-server (8012)
- publishing-frontend

## LocalAgent Notes

- Manager: `Packages/FountainApps/Sources/local-agent-manager/main.swift:1`
- Config (defaults/overrides): `Configuration/local-agent.json:1`
- Health: `http://127.0.0.1:8080/health`
- Script wrapper used by the launcher UI and these dev scripts:
  - `Scripts/launcher:1`

## Common Dev Tasks

- Run focused tests for a package you touched:
  - `swift test --package-path Packages/FountainCore`
  - `swift test --package-path Packages/FountainGatewayKit`
- Explore OpenAPI specs (authoritative for HTTP surfaces):
  - `Packages/FountainSpecCuration/openapi/README.md:1`
- Try examples (no external services required):
  - `swift run --package-path Packages/FountainExamples hello-fountainai-teatro`
  - Semantic Browser server:
    - Build: `swift build --package-path Packages/FountainApps-SemanticBrowser`
    - Run: `swift run --package-path Packages/FountainApps-SemanticBrowser semantic-browser-server`
    - Helper: `Scripts/semantic-browser [build|run]`

## Troubleshooting

- Missing or invalid launcher signature
  - Symptom: process exits early with an error.
  - Fix: run `source Scripts/dev-up env` (or export `LAUNCHER_SIGNATURE` manually).
- Gateway `/chat` times out
  - LocalAgent likely not running or unhealthy. Run `Scripts/launcher start`.
  - Fallback mock auto-starts if LocalAgent can’t become healthy.
  - Logs: `.fountain/logs/local-agent.log` and `.fountain/logs/mock-localagent.log`
- Port conflicts or “Address already in use”
  - The dev-up script now guards against double-starts by checking ports and PIDs.
  - If you started services outside dev-up, use: `Scripts/dev-down --force` to kill listeners on default dev ports.
  - Adjust `PORT` env per service as needed, e.g. `PORT=9000 swift run --package-path Packages/FountainApps gateway-server`.
- Where are logs/pids?
  - `.fountain/logs/*.log` and `.fountain/pids/*.pid`

## CI Smoke

- Run the local smoke script that builds, starts core services with readiness, probes a few endpoints and tears down:
  - `bash Scripts/ci-smoke.sh`
- In CI, a workflow `.github/workflows/ci-smoke.yml` runs this on push/PR and uploads `.fountain/logs` as an artifact for debugging.

## File References

- Workspace aggregator: `Workspace/placeholder.swift:1`
- Launcher signature constant: `Packages/FountainCore/Sources/LauncherSignature/Signature.swift:1`
- Gateway entry: `Packages/FountainApps/Sources/gateway-server/main.swift:1`
- Dev scripts: `Scripts/dev-up`, `Scripts/dev-down`
