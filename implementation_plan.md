# FountainKit OpenAPI-First Plan — Concise Roadmap

Purpose
- Keep every HTTP surface spec-first, generated, and wired through FountainCore transports. Keep this plan short, current, and practical.

Status — Done
- Generator in use across the workspace:
  - Clients: `GatewayAPI`, `PersistAPI`, `SemanticBrowserAPI`, `LLMGatewayAPI` generated (URLSession transport).
  - Servers: `SemanticBrowser`, `Persist`, `Planner` implemented; `Bootstrap` and `FunctionCaller` handlers added in service kits.
  - Gateway control plane served via generated handlers; Gateway tests are green.
  - Executables: `bootstrap-server`, `function-caller-server`, and `baseline-awareness-server` now use `NIOOpenAPIServerTransport` with `/openapi.yaml` fallback.
- UX and infra improvements:
  - Client factory in FountainCore (URLSession transport + default-header middleware).
  - Split `semantic-browser-server` into `Packages/FountainApps-SemanticBrowser`; CI builds it separately.
  - Fixed `/auth/token` date decoding and HTTP framing (Content-Length for non‑chunked).
  - Synced generated handler code to current `swift-openapi-runtime` types (e.g., `OpenAPIValueContainer`, refined enums, `.plainText`).

Status — In Progress
- Switch executables to generated routing:
  - Executables: `function-caller-server` now uses `NIOOpenAPIServerTransport` with `/openapi.yaml` fallback.
- Service migrations (handlers + routing): `Awareness`, `ToolsFactory`, `ToolServer`.
  - Awareness: Implemented generated server handlers and flipped executable.
- Decision: introduce a generated `DNS` client (if needed by consumers).

Next Steps (High Priority)
- Flip `bootstrap-server` and `function-caller-server` to `NIOOpenAPIServerTransport` with `/openapi.yaml` fallback.
- Wire remaining service kits (Awareness, ToolsFactory, ToolServer) to generated handlers.
- Add stricter CI checks: spec lint (`Scripts/openapi-lint.sh`) and “must have generator config” guard per target.
- Retire legacy `FountainCodex` once all clients/servers are generated.

Principles
- OpenAPI is the source of truth; update specs first and regenerate during build.
- Do not commit generated Swift; keep configs (`openapi.yaml` symlink + `openapi-generator-config.yaml`) next to targets.
- Use FountainCore transports; prefer SwiftNIO for servers; URLSession or AsyncHTTPClient for clients.

Quick Map (truth snapshot)
- Gateway (Apps): generated control-plane handlers; tests green.
- Service kits:
  - `SemanticBrowser`, `Persist`, `Planner`: generated server handlers implemented.
  - `Bootstrap`, `FunctionCaller`: generated server handlers implemented in kits; executables still legacy (to flip next).
  - `Awareness`, `ToolsFactory`, `ToolServer`: generator scaffolding underway (Awareness), wiring pending.
- API clients:
  - `GatewayAPI`, `PersistAPI`, `SemanticBrowserAPI`, `LLMGatewayAPI`: generated; adapters use generated clients where applicable.
- Packages: `FountainApps-SemanticBrowser` hosts the semantic browser executable independently.

Validate Locally
- Build everything: `swift build`
- Gateway tests: `swift test --package-path Packages/FountainApps --filter GatewayServerTests`

Maintainers
- Keep this file concise. Update only the Done/In Progress/Next Steps sections as changes land.
