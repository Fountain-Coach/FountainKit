# AGENT — FountainTooling

Scope: `Packages/FountainTooling/**` — OpenAPI curator service/CLI, validation helpers.

Principles
- Curate specs in `Packages/FountainSpecCuration/openapi/**`; no ad‑hoc scans.
- Lint scripts kept deterministic; no network by default.

Testing & TDD
- Unit: schema normalization, lint checks.
- Integration: curator produces expected outputs for fixtures.

CI gates
- Lint matrix (`openapi-lint.sh`) runs in CI; failures block merge.

