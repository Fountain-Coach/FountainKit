# AGENT — Spec Curation (OpenAPI)

This folder is the single source of truth for HTTP contracts. Specs are versioned, linted, and consumed by generators; server/client targets point at these files (directly or via symlink) and never commit generated Swift. We maintain a curated, finite list of specs — no scans.

Versioning and names
Place each service spec under `openapi/v{major}/service-name.yml`. Keep older versions; add new ones instead of rewriting history. For gateway‑related docs, use clear service names that match their owning package.

Index in README
After any change, update `Packages/FountainSpecCuration/openapi/README.md`. Maintain two tables: Gateway (server and plugin surfaces) and Persistence/FountainStore specs. Use a simple status mark (e.g., ✅/❌) and keep entries additive.

Lint and validate
- Local lint: `Packages/FountainSpecCuration/openapi/lint-matrix.sh <spec>` (or `--list`).
- CI lint: `Scripts/openapi/openapi-lint.sh`.
- Curated list validator: `Scripts/openapi/validate-curated-specs.sh` keeps `Configuration/curated-openapi-specs.json` in sync.

Curator as source of truth
Normalize and bundle specs with the FountainAI OpenAPI Curator: service at `Packages/FountainTooling/Sources/openapi-curator-service` (HTTP `POST /curate`) or CLI at `Packages/FountainTooling/Sources/openapi-curator-cli`. Curated output is authoritative and may be submitted to ToolsFactory when appropriate.

Swift OpenAPI Generator
- Consuming targets provide an `openapi.yaml` in their source directory (or a symlink into this folder) and an `openapi-generator-config.yaml` declaring `generate: [types, server]` or `generate: [types, client]` (use `filter.paths` to scope operations).
- Shared models live in `FountainCore` (or another shared kit); configure generators to omit duplicate schema emission.
- Regenerate by running `swift build`; do not hand‑edit generated Swift.

Repository linkage
Gateway server lives at `Packages/FountainApps/Sources/gateway-server`; gateway plugins and shared utilities live in `Packages/FountainGatewayKit`. Keep spec names aligned with targets so editors can jump from spec to code. Other services follow the same pattern under `Packages/FountainServiceKit-*/Sources/*Service` and executables under `Packages/FountainApps/Sources/*-server`.

Active plans
See `Packages/FountainSpecCuration/openapi/arcspec_studio_plan.md` and `Packages/FountainSpecCuration/openapi/gateway_generator_plan.md` for cross‑cutting work across specs, generators, and UI.

Following these rules keeps specs versioned, linted, and wired cleanly into the generators, Gateway, and FountainStore.
