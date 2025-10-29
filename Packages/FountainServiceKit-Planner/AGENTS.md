# AGENT — Planner Service

What: Planner turns objectives into deterministic tool steps. Spec: `Packages/FountainServiceKit-Planner/Sources/PlannerService/openapi.yaml`. Profiles constrain tool availability; unsafe ops are rejected up front. Prompts/configurations are versioned and testable.

Build/test
- Build: `swift build --package-path Packages/FountainServiceKit-Planner -c debug`
- Tests: `swift test --package-path Packages/FountainServiceKit-Planner -c debug`

Testing
Use golden fixtures for objective→steps mapping (AudioTalk tasks). Integration verifies deterministic execution via FunctionCaller. End‑to‑end, plan a complete AudioTalk flow (parse → map → apply). New planner profiles must ship with tests for their patterns.
