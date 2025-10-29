# AGENT — FunctionCaller Service

What: FunctionCaller catalogs and executes functions described by OpenAPI operations. Registration is idempotent; list formats are stable; errors follow a consistent shape. Spec: `Packages/FountainServiceKit-FunctionCaller/Sources/FunctionCallerService/openapi.yaml`.

How
- Honor templated paths and a base prefix via `FUNCTION_CALLER_BASE_URL`.
- Keep the catalog schema curated and deterministic; avoid implicit scans.
- Prefer explicit corpora to scope tool visibility.

Build/test
- Build: `swift build --package-path Packages/FountainServiceKit-FunctionCaller -c debug`
- Tests: `swift test --package-path Packages/FountainServiceKit-FunctionCaller -c debug`

Integration
Exercise register/list/execute flows and any catalog persistence. End‑to‑end, a Planner → FunctionCaller → target service scenario runs in AudioTalk. CI builds and tests this package; smoke targets run via Studio autostart or CI smoke.
