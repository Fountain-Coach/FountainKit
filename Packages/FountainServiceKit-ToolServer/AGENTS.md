# AGENT — ToolServer Service

Scope: `Packages/FountainServiceKit-ToolServer/**` — direct tool execution.
Spec: `Packages/FountainServiceKit-ToolServer/Sources/ToolServer/openapi.yaml`.

Principles
- Safety: input size/time budgets, sandboxing as required.

Testing & TDD
- Unit: request validation and safety guards.
- Integration: minimal tool runs; health.

CI gates
- Build + tests; Studio smoke optional.

