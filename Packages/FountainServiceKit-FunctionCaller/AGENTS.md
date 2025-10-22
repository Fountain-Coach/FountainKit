# AGENT — FunctionCaller Service

Scope: `Packages/FountainServiceKit-FunctionCaller/**` — function catalog + execution surface.
Spec: `Packages/FountainServiceKit-FunctionCaller/Sources/FunctionCallerService/openapi.yaml`.

Principles
- Curated function catalog schema; templated paths; base prefix via `FUNCTION_CALLER_BASE_URL`.
- Idempotent registration; consistent error shapes.

Testing & TDD
- Unit: path templating, arg validation (where implemented), base prefix logic.
- Integration: register/list/execute flows; persistence of catalog if applicable.
- E2E: Planner → FunctionCaller → target service execution in AudioTalk.

CI gates
- Build + tests; smoke targets run in Studio autostart or CI smoke.

