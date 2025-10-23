# AGENT — Scripts/openapi (spec lint and validation)

Scope: `Scripts/openapi/**`.

Purpose
- Keep OpenAPI‑specific tooling together and documented.
- Enforce curated list discipline and linter parity in CI.

Included tools
- `openapi-lint.sh` — Lints all OpenAPI files using Redocly CLI (or a custom linter via `OPENAPI_LINT_CLI`).
- `validate-curated-specs.sh` — Verifies `Configuration/curated-openapi-specs.json` paths exist and cover all server specs.

Usage
- Lint: `bash Scripts/openapi/openapi-lint.sh`
- Validate curated list: `bash Scripts/openapi/validate-curated-specs.sh`

CI
- Either call these scripts directly or use the legacy wrappers in `Scripts/` (kept for compatibility).

