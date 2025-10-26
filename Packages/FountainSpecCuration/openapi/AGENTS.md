# OpenAPI directory conventions

This folder is the source of truth for our HTTP contracts. Keep specs versioned, linted, and discoverable so they feed cleanly into generation and the control plane.

Versioning and names
Place each service spec in `openapi/v{major}/service-name.yml`. Gateway plugin specs use the `*-gateway.yml` suffix. Don’t delete or rewrite existing links: new versions append to the index so history remains intact.

Index in README
After any change, update `openapi/README.md`. We maintain two tables there: Gateway plugins (owner and status) and Persistence/FountainStore specs. Use a simple status mark (e.g., ✅/❌) and keep entries additive.

Validation
Lint locally with `openapi/lint-matrix.sh <spec>` (or `--list`) and in CI via `Scripts/openapi/openapi-lint.sh`. Redocly failures block merges. Specs end with the required copyright line: `© 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.`

Repository linkage
Each new Gateway spec should map to a Swift package under `libs/GatewayPlugins/` and a `+GatewayPlugin.swift` registration in `services/GatewayServer/GatewayApp`. Keep names aligned so readers can jump between spec and code.

Curator as single source
After editing, invoke the FountainAI OpenAPI Curator via `POST /curate` with every `file://openapi/...` document and a `corpusId` for the bundle. The curated output is the authoritative copy and can be submitted to the Tools Factory when `submitToToolsFactory` is `true`.

Active plans
See `openapi/arcspec_studio_plan.md` for ArcSpec and Studio implementation work. We use that doc to track changes that cross spec, generator, and UI.

Following these guidelines keeps specs versioned, linted, and wired cleanly into Gateway and FountainStore.
