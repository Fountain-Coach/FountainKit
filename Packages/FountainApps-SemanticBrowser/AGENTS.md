FountainApps-SemanticBrowser — Agent Guide

Scope: This file applies to the `Packages/FountainApps-SemanticBrowser` package.

Purpose
- This package wraps the Semantic Browser service library (`FountainServiceKit-SemanticBrowser`) into a runnable executable (`semantic-browser-server`).
- It should remain lightweight and only concern process wiring, transport setup, env var handling, and readiness endpoints.

Agent rules
- Do NOT add OpenAPI generator configs here; keep specs/configs in the service kit. This package only hosts an executable.
- Use `FountainRuntime.NIOOpenAPIServerTransport` to register generated handlers and `NIOHTTPServer` to serve traffic.
- Keep non‑API endpoints (e.g. `/metrics`, `/openapi.yaml`) behind a simple fallback `HTTPKernel`.
- Engine selection is driven by env vars: `SB_CDP_URL` (CDP), `SB_BROWSER_CLI` + `SB_BROWSER_ARGS`, else `URLFetchBrowserEngine`.
- Favor minimal dependencies. If you add new ones, document why in the README.

Build & run
- Build: `swift build --package-path Packages/FountainApps-SemanticBrowser`
- Run: `swift run --package-path Packages/FountainApps-SemanticBrowser semantic-browser-server`
- Helper: `Scripts/semantic-browser [build|run]`

CI expectations
- CI builds this package separately from `FountainApps` to avoid dragging CNIO/NIO extras into unrelated tests.

