# AGENT — Planner Service

Scope: `Packages/FountainServiceKit-Planner/**` — reasoning to tool steps.
Spec: `Packages/FountainServiceKit-Planner/Sources/PlannerService/openapi.yaml`.

Principles
- Profiles constrain tool set; deterministic step shapes; reject unsafe operations.
- Keep prompts/configurations versioned and testable.

Testing & TDD
- Unit: objective → steps mapping for AudioTalk tasks (golden tests).
- Integration: steps executed by FunctionCaller deterministically.
- E2E: full AudioTalk scenario (parse → map → apply) planned via service.

CI gates
- Build + tests; planner profiles must include tests for new patterns.

