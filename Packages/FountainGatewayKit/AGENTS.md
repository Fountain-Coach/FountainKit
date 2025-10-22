# AGENT — FountainGatewayKit (Gateway Plugins & Orchestrator)

Scope: `Packages/FountainGatewayKit/**` — gateway persona orchestrator, plugins (auth,
rate‑limit, policy, security/budget, payload inspection, role health, etc.), and publishing frontend.

Principles
- Plugins are composable and side‑effect free; enforce time/size budgets.
- Route reload endpoint `/admin/routes/reload` remains stable.
- OpenAPI‑first: gateway spec at `Packages/FountainApps/Sources/gateway-server/openapi.yaml`.

Testing & TDD
- Unit: plugin behaviors and failure paths (auth, limits, budget, policy checks).
- Integration: gateway server boots with plugin chain; route reload succeeds.
- E2E: after regenerate, `/admin/routes` contains curated minimal set.

CI gates
- Build + tests for this package; gateway server smoke started by scripts.

Maintenance
- Any new plugin must include tests and be added to curated route exposure rules.

