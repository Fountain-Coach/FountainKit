# ChatKit-JS Development Environment (Vite)

This is a lightweight dev environment for iterating on ChatKit integration
against the FountainKit gateway without fighting CORS. It runs a local Vite
server on a fixed port and proxies API calls to the gateway.

## Prerequisites

- Node.js 18+ and `pnpm` (or `npm`)
- Swift toolchain for building `gateway-server`

## One-click dev

From the repo root:

```sh
./Workspace/chatkit-dev/run-dev.sh
```

The script:

1. Launches `gateway-server` on port `8010` (with required launcher signature)
2. Starts Vite on port `5173`
3. Opens the dev URL

Stop with `Ctrl+C`; both processes will terminate.

## Manual usage

```sh
# Terminal A
swift run --package-path Packages/FountainApps gateway-server

# Terminal B
cd Workspace/chatkit-dev
pnpm install
pnpm dev
```

Open http://127.0.0.1:5173 and use the controls to bootstrap a session.

## Notes

- The Vite dev server proxies `/chatkit` and `/health` to the gateway (port
  8010), so the page origin remains stable during development.
- The app uses the shared helper from `Public/chatkit.js` and surfaces
  lifecycle logs in-page for quicker debugging.
