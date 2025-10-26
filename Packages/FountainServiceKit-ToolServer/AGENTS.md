# AGENT — ToolServer Service

ToolServer executes tools directly. Spec: `Packages/FountainServiceKit-ToolServer/Sources/ToolServer/openapi.yaml`. Safety is paramount: enforce input size/time budgets and sandbox when required.

Unit tests cover request validation and safety guards; integration runs a minimal tool set and checks health. CI builds and tests this package; Studio smoke is optional.
