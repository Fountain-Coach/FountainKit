# FountainKit OpenAPI-First Plan — Concise Roadmap

Purpose
- Keep every HTTP surface spec-first, generated, and wired through FountainCore transports. Keep this plan short, current, and practical.

Status — Done
- Generator in use across the workspace:
  - Clients: `GatewayAPI`, `PersistAPI`, `SemanticBrowserAPI`, `LLMGatewayAPI` generated (URLSession transport).
  - Servers: `SemanticBrowser`, `Persist`, `Planner` implemented; `Bootstrap` and `FunctionCaller` handlers added in service kits.
  - Gateway control plane served via generated handlers; Gateway tests are green.
  - Executables: `bootstrap-server`, `function-caller-server`, `baseline-awareness-server`, `tools-factory-server`, and `tool-server` now use `NIOOpenAPIServerTransport` with `/openapi.yaml` fallback.
- Delivered generated DNS client with URLSession + AsyncHTTPClient support for cross-platform consumption.
- UX and infra improvements:
  - Client factory in FountainCore (URLSession transport + default-header middleware).
  - Split `semantic-browser-server` into `Packages/FountainApps-SemanticBrowser`; CI builds it separately.
  - Fixed `/auth/token` date decoding and HTTP framing (Content-Length for non‑chunked).
  - Synced generated handler code to current `swift-openapi-runtime` types (e.g., `OpenAPIValueContainer`, refined enums, `.plainText`).
  - Tool Server now managed via Docker Compose with a dedicated manager and compose file; handlers run tools via `docker compose run`.
  - Tool Server supports startup image pull (TOOLSERVER_PULL_ON_START) and a public status endpoint returning compose availability and services.
  - CI runs `Scripts/openapi-lint.sh` on Ubuntu and macOS runners before Swift builds/tests.
  - SwiftPM build plugin enforces presence of `openapi-generator-config.yaml` for generated targets.
  - Completed Linux `FoundationNetworking` audit for URLSession-based transports, CLIs, and tests.
  - CI runs a workspace `swift build --explicit-target-dependency-import-check` on macOS and Linux, and `Scripts/ci-smoke.sh` now drives generated ChatKit flows via `gateway-ci-smoke`.

Status — In Progress
- Service migrations: Completed for Awareness, ToolsFactory, ToolServer (handlers + routing).

Next Steps (High Priority)
1. **Spec + Generator Enforcement**
   - [x] Land CI guardrail that runs `openapi/lint-matrix.sh` (Redocly) on Linux and macOS runners.
   - [x] Enforce “generator config present” for every target by adding a SwiftPM plugin check (fails the build when missing).
2. **Cross-Platform Client Coverage**
   - [x] Evaluate the need for a generated DNS client (see `OPENAPI_COVERAGE.md`) and implement it with URLSession + AsyncHTTPClient transports.
   - [x] Migrate remaining pending clients (`FunctionCallerAPI`, `BootstrapAPI`, `ToolsFactoryAPI`, `FKOpsAPI`, `AwarenessAPI`) to generated implementations and validate parity on Linux/macOS.
3. **Runtime Compatibility Sweep**
   - [x] Audit `FountainCore` transports for FoundationNetworking availability on Linux and provide shims where required.
   - [ ] Add integration smoke tests for a representative client/server pair running on both Darwin and Linux Swift toolchains (macOS ChatKit smoke in place; Linux execution pending).
4. **Legacy Decommissioning**
   - [ ] Retire `FountainCodex` once generated clients pass the cross-platform smoke tests.
5. **Tool Server Hardening**
   - [ ] Add health checks, image pinning, and CI smoke (compose optional) with environment guards.

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
- Use `Packages/FountainSpecCuration/openapi/lint-matrix.sh` for per-spec validation and CI parity.
- Gateway tests: `swift test --package-path Packages/FountainApps --filter GatewayServerTests`

Maintainers
- Keep this file concise. Update only the Done/In Progress/Next Steps sections as changes land.
