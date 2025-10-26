FountainApps-SemanticBrowser — Agent Guide

This package turns the Semantic Browser service library (`FountainServiceKit-SemanticBrowser`) into a runnable executable (`semantic-browser-server`). Keep it lightweight: focus on process wiring, transport setup, env handling, and a small readiness surface. All specs/configs live in the service kit; don’t add OpenAPI generator configs here.

Use `FountainRuntime.NIOOpenAPIServerTransport` to register generated handlers and `NIOHTTPServer` to serve traffic. Non‑API endpoints like `/metrics` and `/openapi.yaml` can sit behind a simple fallback `HTTPKernel`. Engine selection is controlled by env vars: `SB_CDP_URL` for CDP, `SB_BROWSER_CLI`/`SB_BROWSER_ARGS` for a CLI engine, otherwise fall back to `URLFetchBrowserEngine`. Favor minimal dependencies and document any additions in the README.

Build with `swift build --package-path Packages/FountainApps-SemanticBrowser` and run with `swift run --package-path Packages/FountainApps-SemanticBrowser semantic-browser-server`. A helper wrapper exists at `Scripts/semantic-browser [build|run]`. CI builds this package separately from `FountainApps` to keep CNIO/NIO extras out of unrelated test jobs.
