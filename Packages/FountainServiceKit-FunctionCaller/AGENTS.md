# AGENT — FunctionCaller Service

FunctionCaller is the function catalog and execution surface. The OpenAPI spec lives at `Packages/FountainServiceKit-FunctionCaller/Sources/FunctionCallerService/openapi.yaml`. Keep a curated catalog schema, use templated paths, and honor a base prefix via `FUNCTION_CALLER_BASE_URL`. Registration is idempotent and errors follow a consistent shape.

Tests cover path templating, argument validation (where implemented), and base‑prefix logic. Integration exercises register/list/execute flows and catalog persistence (if present). End‑to‑end, a Planner → FunctionCaller → target service scenario runs in AudioTalk. CI builds and tests this package; smoke targets run via Studio autostart or CI smoke.
