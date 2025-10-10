# FountainKit OpenAPI-First Plan — Concise Roadmap

Purpose
- Keep every HTTP surface spec-first, generated, and wired through FountainCore transports. Keep this plan short, current, and practical.

Status — Done
- Generator in use across the workspace:
  - Clients: `GatewayAPI`, `PersistAPI`, `SemanticBrowserAPI`, `LLMGatewayAPI` generated (URLSession transport).
  - Servers: `SemanticBrowser`, `Persist`, `Planner` implemented; `Bootstrap` and `FunctionCaller` handlers added in service kits.
  - Gateway control plane served via generated handlers; Gateway tests are green.
  - Executables: `bootstrap-server`, `function-caller-server`, `baseline-awareness-server`, `tools-factory-server`, and `tool-server` now use `NIOOpenAPIServerTransport` with `/openapi.yaml` fallback.
- UX and infra improvements:
  - Client factory in FountainCore (URLSession transport + default-header middleware).
  - Split `semantic-browser-server` into `Packages/FountainApps-SemanticBrowser`; CI builds it separately.
  - Fixed `/auth/token` date decoding and HTTP framing (Content-Length for non‑chunked).
  - Synced generated handler code to current `swift-openapi-runtime` types (e.g., `OpenAPIValueContainer`, refined enums, `.plainText`).
  - Tool Server now managed via Docker Compose with a dedicated manager and compose file; handlers run tools via `docker compose run`.

Status — In Progress
- Service migrations: Completed for Awareness, ToolsFactory, ToolServer (handlers + routing).
- Decision: introduce a generated `DNS` client (if needed by consumers).

Next Steps (High Priority)
- Add stricter CI checks: spec lint (`Scripts/openapi-lint.sh`) and “must have generator config” guard per target.
- Evaluate/implement DNS client target if required by consumers.
- Retire legacy `FountainCodex` once all clients/servers are generated.
 - Tool Server hardening: add health checks, image pinning, and CI smoke (compose optional) with env guards.

Principles
- OpenAPI is the source of truth; update specs first and regenerate during build.
- Do not commit generated Swift; keep configs (`openapi.yaml` symlink + `openapi-generator-config.yaml`) next to targets.
- Use FountainCore transports; prefer SwiftNIO for servers; URLSession or AsyncHTTPClient for clients.

Quick Map (truth snapshot)
- Gateway (Apps): generated control-plane handlers; tests green.
- Service kits:
  - `SemanticBrowser`, `Persist`, `Planner`, `Bootstrap`, `FunctionCaller`, `Awareness`, `ToolsFactory`, `ToolServer`: generated handlers implemented; executables on NIOOpenAPIServerTransport.
- API clients:
  - `GatewayAPI`, `PersistAPI`, `SemanticBrowserAPI`, `LLMGatewayAPI`: generated; adapters use generated clients where applicable.
- Packages: `FountainApps-SemanticBrowser` hosts the semantic browser executable independently.

Validate Locally
- Build everything: `swift build`
- Gateway tests: `swift test --package-path Packages/FountainApps --filter GatewayServerTests`

Maintainers
- Keep this file concise. Update only the Done/In Progress/Next Steps sections as changes land.
