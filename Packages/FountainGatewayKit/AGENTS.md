# AGENT — FountainGatewayKit (gateway plugins and orchestrator)

What: `Packages/FountainGatewayKit/**` implements the gateway persona orchestrator, plugins (auth, rate‑limits, policy, security/budget, payload inspection, role health), and a minimal publishing frontend. Plugins are composable and side‑effect‑free; the chain enforces time/size budgets. The reload endpoint `/admin/routes/reload` is a stable contract. Gateway is OpenAPI‑first — spec at `Packages/FountainApps/Sources/gateway-server/openapi.yaml`.

Where code lives
- Orchestrator and shared utils: `Packages/FountainGatewayKit/Sources/**`
- Gateway server target: `Packages/FountainApps/Sources/gateway-server` (registers generated handlers and wires plugins)
- Tests: `Packages/FountainApps/Tests/GatewayServerTests` (integration) and `Packages/FountainGatewayKit/Tests` (unit)

Build/test
- Build server: `swift build --package-path Packages/FountainApps -c debug --target gateway-server`
- Run server: `swift run --package-path Packages/FountainApps gateway-server`
- Tests: `swift test --package-path Packages/FountainApps -c debug --filter GatewayServerTests`

Testing focus
Unit tests cover plugin behaviors and failure paths (auth, limits, budgets, policy checks). Integration boots a real plugin chain and verifies reload succeeds; end‑to‑end, regenerate → `/admin/routes` contains the curated minimal set. Scripts start the server for smoke (`Scripts/ci/ci-smoke.sh`).

Adding a plugin
Include unit/integration tests and update curated route exposure rules so the control plane remains predictable. Keep plugin APIs additive and document budget semantics.
