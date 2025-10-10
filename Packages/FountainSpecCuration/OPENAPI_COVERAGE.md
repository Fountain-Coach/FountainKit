# OpenAPI Coverage and Adoption

This document tracks ownership of each curated OpenAPI spec and adoption of Apple’s Swift OpenAPI Generator across FountainKit.

Notes
- Server adoption means the target declares the `OpenAPIGenerator` plugin, provides `openapi.yaml` (symlink into `FountainSpecCuration`), and implements generated server protocol conformances wired through `FountainRuntime` transports.
- Client adoption means a target in `FountainAPIClients` declares the plugin and can construct a generated client (call‑site migrations may still be pending).
- Non‑API endpoints (e.g. `/metrics`) may remain manual via fallback kernels.

| Spec | Owner target(s) | Server adoption | Client adoption |
| --- | --- | --- | --- |
| `v1/gateway.yml` | `FountainApps/gateway-server` | Generator enabled (scoped control plane) | `FountainAPIClients/GatewayAPI` generator enabled |
| `v1/semantic-browser.yml` | `FountainServiceKit-SemanticBrowser/SemanticBrowserService` | Generator enabled | `FountainAPIClients/SemanticBrowserAPI` generator enabled |
| `v1/persist.yml` | `FountainServiceKit-Persist/PersistService` | Generator enabled | `FountainAPIClients/PersistAPI` generator enabled |
| `v1/planner.yml` | `FountainServiceKit-Planner/PlannerService` | Generator enabled | Pending |
| `v1/function-caller.yml` | `FountainServiceKit-FunctionCaller/FunctionCallerService` | Generator enabled | Pending |
| `v1/bootstrap.yml` | `FountainServiceKit-Bootstrap/BootstrapService` | Generator enabled | Pending |
| `v1/tools-factory.yml` | `FountainServiceKit-ToolsFactory/ToolsFactoryService` | Generator enabled | Pending |
| `v1/tool-server.yml` | `FountainServiceKit-ToolServer/ToolServerService` | Generator enabled (OpenAPIHandlers wired) | N/A |
| `v1/fk-ops.yml` | `FountainServiceKit-FKOps/FKOpsService` | Generator enabled | Pending |
| `v1/baseline-awareness.yml` | `FountainServiceKit-Awareness/AwarenessService` | Generator enabled | Pending |
| `v1/dns.yml` | `FountainCore/FountainRuntime` | Pending | Pending |
| `v1/llm-gateway.yml` | Gateway plugin (no standalone server) | N/A | `FountainAPIClients/LLMGatewayAPI` generator enabled |
| `v1/openapi-curator.yml` | `FountainTooling` | Pending | N/A |

Status last updated: 2025‑10‑10 (fk ops + tool server audit)

## Executable Task List

1. **Close Pending Client Gaps**
   - [ ] Promote `PlannerAPI`, `FunctionCallerAPI`, `BootstrapAPI`, and `ToolsFactoryAPI` to generated clients and confirm they compile and run on both macOS and Linux.
   - [ ] Wire `FKOpsAPI` and `AwarenessAPI` consumers to generated clients; exercise them against live servers on Linux CI.
2. **Deliver DNS Coverage**
   - [ ] Finalize the curated `v1/dns.yml` spec (lint + curator submission) and add the generator plugin to the owning target.
   - [ ] Implement a multi-transport DNS client (URLSession for Darwin, AsyncHTTPClient for Linux) and add regression tests that run in cross-platform CI.
3. **Curator + Spec Automation**
   - [ ] Hook this coverage table into CI so that pending entries fail the build if the owning target lacks generator metadata.
   - [ ] Emit a JSON snapshot of this coverage data for other toolchains to consume (ensures parity between macOS and Linux builds).

