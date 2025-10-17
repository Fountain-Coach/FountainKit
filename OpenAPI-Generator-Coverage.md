# OpenAPI Generator Coverage Report

_Date: 2025-10-23 (UTC)_
_Git HEAD: work (`6316b06` — "Merge pull request #38 from Fountain-Coach/codex/check-git-history-and-implement-tooling-updates")_

## Coverage overview
- [`Packages/FountainSpecCuration/openapi/README.md`](Packages/FountainSpecCuration/openapi/README.md) now reflects generator adoption for every curated service. All runtime services under FountainServiceKit ship `openapi-generator-config.yaml` files and generated handler shims:
  - `BootstrapService`, `FunctionCallerService`, `PlannerService`, `PersistService`, `SpeechAtlasService`, `AwarenessService`, `FKOpsService`, `ToolsFactoryService`, and `ToolServerService` use the Swift OpenAPI generator for their servers, pairing with dedicated client targets in `FountainAPIClients` where applicable.
  - `gateway-server` continues to source both its control plane and ChatKit routes from `v1/gateway.yml`, with CI exercising the generated client via `Packages/FountainApps/Sources/gateway-ci-smoke`.
  - Client coverage now spans `GatewayAPI`, `PersistAPI`, `SemanticBrowserAPI`, `PlannerAPI`, `FunctionCallerAPI`, `BootstrapAPI`, `ToolsFactoryAPI`, `SpeechAtlasAPI`, `AwarenessAPI`, `FKOpsAPI`, `DNSAPI`, and `LLMGatewayAPI`.

## Outstanding gaps
- `v1/tool-server.yml` lacks a first-party generated client; service implementers use manual HTTP calls.
- `v1/dns.yml` is curated but not yet wired into a Swift server target; only the generated `DNSAPI` client consumes it.
- `v1/llm-gateway.yml` updated to model `ChatResponse` and `stream` SSE behavior. Engraver Studio uses the generated client for non-streaming calls; SSE streaming remains via a lightweight adapter until generator-level streaming lands.
- `v1/openapi-curator.yml` has neither server nor client bindings; the service and CLI continue to hand-roll transports.

## Git history reference
- `39ce5b7` – migrated the bootstrap stack onto generated transports.
- `15dbdc3` – adopted the generator for Planner server handlers.
- `9a62546` – switched Baseline Awareness to generated handlers.
- `2ef1792` – introduced generator scaffolding for Tools Factory and Tool Server.
- `9aa782e` – added FK Ops spec-driven management service.
- `5729994` – migrated Gateway API to generated client plumbing.
