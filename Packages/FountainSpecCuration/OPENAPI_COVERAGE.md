# OpenAPI Coverage and Adoption

This document tracks ownership of each curated OpenAPI spec and adoption of Apple’s Swift OpenAPI Generator across FountainKit.

Notes
- Server adoption means the target declares the `OpenAPIGenerator` plugin, provides `openapi.yaml` (symlink into `FountainSpecCuration`), and implements generated server protocol conformances wired through `FountainRuntime` transports.
- Client adoption means a target in `FountainAPIClients` declares the plugin and can construct a generated client (call‑site migrations may still be pending).
- Non‑API endpoints (e.g. `/metrics`) may remain manual via fallback kernels.

| Spec | Owner target(s) | Server adoption | Client adoption |
| --- | --- | --- | --- |
| `v1/gateway.yml` | `FountainApps/gateway-server` | Generator enabled (scoped control plane) | N/A |
| `v1/semantic-browser.yml` | `FountainServiceKit-SemanticBrowser/SemanticBrowserService` | Generator enabled | `FountainAPIClients/SemanticBrowserAPI` generator enabled |
| `v1/persist.yml` | `FountainServiceKit-Persist/PersistService` | Generator enabled | `FountainAPIClients/PersistAPI` generator enabled |
| `v1/planner.yml` | `FountainServiceKit-Planner/PlannerService` | Generator enabled | Pending |
| `v1/function-caller.yml` | `FountainServiceKit-FunctionCaller/FunctionCallerService` | Pending | Pending |
| `v1/bootstrap.yml` | `FountainServiceKit-Bootstrap/BootstrapService` | Pending | Pending |
| `v1/tools-factory.yml` | `FountainServiceKit-ToolsFactory/ToolsFactoryService` | Pending | Pending |
| `v1/tool-server.yml` | `FountainServiceKit-ToolServer` | Manual router, no generator | N/A |
| `v1/dns.yml` | TBC | Pending | Pending |
| `v1/llm-gateway.yml` | Gateway plugin (no standalone server) | N/A | N/A |
| `v1/openapi-curator.yml` | `FountainTooling` | Pending | N/A |

Status last updated: 2025‑10‑10

