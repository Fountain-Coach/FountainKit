# semantic-browser-server

Standalone executable that exposes the Semantic Browser & Dissector API based on the curated OpenAPI spec.

- Package: `Packages/FountainApps-SemanticBrowser`
- Binary: `semantic-browser-server`
- Default port: `8007` (override with `SEMANTIC_BROWSER_PORT` or `PORT`)

## Build

```
swift build --package-path Packages/FountainApps-SemanticBrowser
```

## Run

```
swift run --package-path Packages/FountainApps-SemanticBrowser semantic-browser-server
```

Shortcut helper:

```
Scripts/semantic-browser build
Scripts/semantic-browser run
```

## Engine selection

The server selects a browser engine at startup based on env vars:
- `SB_CDP_URL` — WebSocket URL for a remote Chrome DevTools Protocol browser.
- `SB_BROWSER_CLI` — Path to a local headless browser CLI; optional `SB_BROWSER_ARGS` for extra flags.
- If neither is provided, it falls back to a simple `URLFetchBrowserEngine`.

## OpenAPI & transport

- The target symlinks `openapi.yaml` from `FountainServiceKit-SemanticBrowser` and registers generated handlers.
- Transport is bridged via `FountainRuntime.NIOOpenAPIServerTransport` into the shared `NIOHTTPServer`.
- Non‑API endpoints like `/metrics` and `/openapi.yaml` are handled by the fallback kernel.

## Readiness

- Readiness probe: `GET /metrics` (text)
- Health (spec): `GET /v1/health` (JSON)

## Notes for contributors

- Keep generator configuration in the service kit; this package wires the executable only.
- Do not add heavy dependencies here unless specific to the executable.
- Prefer updating the service kit for API/handler changes and re-run `swift build` to regenerate.
