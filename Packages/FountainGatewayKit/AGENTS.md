# AGENT — FountainGatewayKit (gateway plugins and orchestrator)

`Packages/FountainGatewayKit/**` contains the gateway persona orchestrator and its plugins (authentication, rate‑limits, policy, security/budget, payload inspection, role health) plus the publishing frontend. Plugins are composable and side‑effect‑free, and the chain must enforce time/size budgets. The reload endpoint `/admin/routes/reload` is a stable contract. Gateway remains OpenAPI‑first — see `Packages/FountainApps/Sources/gateway-server/openapi.yaml`.

Tests cover plugin behaviors and failure paths (auth, limits, budgets, policy checks). Integration bootstraps the gateway with a real plugin chain and verifies that route reload succeeds; end‑to‑end, a regenerate step leads to `/admin/routes` containing the curated minimal set. CI builds and tests this package; scripts start the server for smoke.

When adding a plugin, include tests and update curated route exposure rules so the control plane stays predictable.
