# AGENT — ToolServer Service

What: ToolServer executes tools directly. Spec: `Packages/FountainServiceKit-ToolServer/Sources/ToolServer/openapi.yaml`. Safety is paramount: enforce input size/time budgets and sandbox when required.

Build/test
- Build: `swift build --package-path Packages/FountainServiceKit-ToolServer -c debug`
- Tests: `swift test --package-path Packages/FountainServiceKit-ToolServer -c debug`

Testing
Unit covers request validation and safety guards; integration runs a minimal tool set and checks health. CI builds/tests this package; Studio smoke is optional.
