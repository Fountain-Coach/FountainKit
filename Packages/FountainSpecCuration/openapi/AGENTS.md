# OpenAPI Directory Conventions

1. **Versioned specs**  
   - Place each service spec in `openapi/v{major}/service-name.yml`.  
   - Gateway plugins use the `*-gateway.yml` suffix.

2. **README maintenance**  
   - After adding or updating a spec, update `openapi/README.md`.  
   - Maintain two tables:
     - **Gateway Plugins** – all plugin specs for the Gateway layer, with owner and completion status.
     - **Persistence/FountainStore** – specs for the FountainStore persistence layer.
   - Mark the status column (e.g., ✅/❌) to reflect task completion.
   - Do **not** delete or rewrite existing spec links—only append entries so the README remains a versioned index of every OpenAPI document.

3. **Validation & copyright**
   - Run `openapi/lint-matrix.sh <spec>` (or `--list`) after any edits to ensure Redocly passes.
   - End every spec with `© 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.`

4. **Repository linkage**
   - Each new gateway spec should have a corresponding Swift package under `libs/GatewayPlugins/` and a registration file `+GatewayPlugin.swift` in `services/GatewayServer/GatewayApp`.

5. **Curatory requirement**
   - After editing any spec, invoke the FountainAI OpenAPI Curator via `POST /curate` with a list of every `file://openapi/...` document and a `corpusId` for the bundle.
   - The curated output is the single source of truth and may be submitted to the Tools Factory when `submitToToolsFactory` is `true`.

## Active Plans

- **ArcSpec & Studio Implementation Plan** — `openapi/arcspec_studio_plan.md`

Following these guidelines keeps OpenAPI specs discoverable, versioned, and consistently integrated with the Gateway and FountainStore layers.
