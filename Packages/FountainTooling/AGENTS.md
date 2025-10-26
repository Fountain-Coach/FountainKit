# AGENT — FountainTooling (OpenAPI curation and validation)

`Packages/FountainTooling/**` contains the OpenAPI curator (service/CLI) and validation helpers. Specs are curated under `Packages/FountainSpecCuration/openapi/**`; avoid ad‑hoc scans. Keep lint scripts deterministic and offline by default.

Unit tests cover schema normalization and lint checks; integration ensures the curator produces the expected outputs for fixtures. CI runs the lint matrix via `Scripts/openapi/openapi-lint.sh`, and failures block merges.
