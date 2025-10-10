# FountainKit OpenAPI-First Adoption Plan (Apple Swift OpenAPI Generator)

This plan moves all HTTP surfaces to spec-driven development using Apple’s Swift OpenAPI Generator, keeps servers SwiftNIO-based, and removes bespoke OpenAPI codegen. It is structured as concrete milestones that keep the build green while migrating incrementally.

Background snapshot
- Curated specs exist under `Packages/FountainSpecCuration/openapi/v1` (gateway, services, plugins).
- No target currently uses `OpenAPIGeneratorPlugin`; no `openapi.yaml` or `openapi-generator-config.yaml` next to sources.
- Clients (`FountainAPIClients`) are hand-written on top of a URLSession wrapper; servers use a custom SwiftNIO HTTP server (`FountainRuntime.NIOHTTPServer`).
- A custom OpenAPI codegen lives in `FountainCore/FountainCodex` and a stub `clientgen-service` exists in `FountainTooling`.

Milestone 0 — Baseline + Gaps (1–2 days)
- Inventory & ownership
  - Map each `openapi/v1/*.yml` to owner target(s) and confirm a single authority per HTTP surface.
  - Update `Packages/FountainSpecCuration/openapi/README.md` with a status table (spec → owner → client/server adoption state).
- Non‑API endpoints stay manual
  - Keep `/metrics`, `/health`, `/live`, `/ready` out of specs and handled by NIO kernels.
- Acceptance: README table present; owners confirmed; no orphaned surfaces.

Milestone 1 — Generator Bootstrap + NIO Transport (3–5 days)
- Dependencies
  - Add `swift-openapi-generator` (plugin) and `swift-openapi-runtime` to packages that will generate code.
  - Clients use `swift-openapi-async-http-client`; UI code may use `swift-openapi-urlsession` where appropriate.
- NIO server transport
  - Introduce `FountainCore` NIO-based `ServerTransport` implementation that bridges to `NIOHTTPServer` (kept minimal initially and unused until pilots switch over).
- Per-target scaffolding
  - Add `openapi.yaml` (symlink into `FountainSpecCuration`) and `openapi-generator-config.yaml` next to each target’s sources.
- Acceptance: `swift build` succeeds with the plugin enabled on one pilot target.

Milestone 2 — Pilot: Semantic Browser (1 week)
- Server
  - Enable generator for `FountainServiceKit-SemanticBrowser` with `generate: [types, server]`.
  - Implement handlers by delegating to existing service logic; keep `/metrics` manual.
  - Start via NIO transport; expose only spec’d endpoints through generated router.
- Client
  - Enable generator for `FountainAPIClients/SemanticBrowserAPI` with `generate: [types, client]` using `OpenAPIAsyncHTTPClient`.
  - Keep hand-written client temporarily; migrate call sites after validation.
- Acceptance: root build green; semantic-browser server responds per spec; smoke `dev-up --all --check` passes.

Milestone 3 — Clients Package Migration (1–1.5 weeks)
- For `FountainAPIClients`, add generator per API target: `GatewayAPI`, `PersistAPI`, `LLMGatewayAPI` (and `DNS` if needed).
- Provide a small factory in `FountainCore` that constructs clients with consistent headers/baseURL.
- Deprecate `ApiClientsCore/RESTClient` after migrating consumers.
- Acceptance: workspace builds; gateway and service kits use generated clients where applicable.

Milestone 4 — Service Server Migration (2–3 weeks, iterative)
- Add generator for each service kit with `generate: [types, server]` and wire handlers:
  - Persist, Planner, FunctionCaller, Bootstrap, ToolsFactory, ToolServer.
- Keep non‑API endpoints manual; serve `/openapi.yaml` if desired for discovery.
- Acceptance: `Scripts/dev-up --all --check` passes; specs and servers match.

Milestone 5 — Gateway Control Plane + Plugins (1–2 weeks)
- Bind generated handlers for gateway control plane (from `gateway.yml`) ahead of plugin routing.
- For plugins that expose HTTP, add per-plugin specs and generator (server) and register handlers in plugin routers.
- Acceptance: gateway returns control-plane responses via generated handlers; plugin routes unaffected.

Milestone 6 — CI, Lint, and Docs (3–4 days)
- CI
  - Lint all OpenAPI docs with `Scripts/openapi-lint.sh`.
  - Ensure a full `swift build` triggers generation for all targets; no generated sources are committed.
  - Optionally probe `/openapi.yaml` on running services and compare to curated sources.
- Docs
  - Update `AGENTS.md` / `ONBOARDING.md` to document generator workflow and review checklist (spec + config + plugin + runtime + transport).
- Acceptance: CI fails on invalid specs or missing generator configuration.

Milestone 7 — Retire Legacy Codegen and Stubs (2–3 days)
- Remove `FountainCore/FountainCodex` OpenAPI codegen and `FountainTooling/clientgen-service`.
- Replace documentation references with Apple generator instructions.
- Acceptance: no references to bespoke codegen remain; workspace builds clean.

Immediate next steps
- Pilot the generator on Semantic Browser (server + client) with minimal risk:
  - Add plugin/runtime deps, `openapi.yaml` symlink, and `openapi-generator-config.yaml`.
  - Keep existing runtime logic and `/metrics` unchanged until generated handlers are validated.

