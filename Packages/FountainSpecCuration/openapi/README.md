# FountainAI OpenAPI Specifications

Versioned service definitions live here. Each YAML file describes a FountainAI service interface.
Persona definitions for Gateway plugins live in `personas/` and are referenced via `x-persona` in the specs.

- Every operation includes `x-fountain.visibility`, `x-fountain.reason`, and `x-fountain.allow-as-tool` extensions for curation.

For a repository‑wide index of OpenAPI coverage and adoption status, see [../OPENAPI_COVERAGE.md](../OPENAPI_COVERAGE.md).

### Recent Updates

- 2025-10-16 – Documented SSE incremental token framing for the ChatKit message stream (`v1/gateway.yml`).

| Service | Version | Owner | Spec |
| --- | --- | --- | --- |
| Auth Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/auth-gateway.yml](v1/auth-gateway.yml) |
| Baseline Awareness Service | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/baseline-awareness.yml](v1/baseline-awareness.yml) |
| Bootstrap Service | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/bootstrap.yml](v1/bootstrap.yml) |
| Budget Breaker Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/budget-breaker-gateway.yml](v1/budget-breaker-gateway.yml) |
| ChatKit Gateway Plugin | 0.1.0 | Contexter alias Benedikt Eickhoff | [v1/chatkit-gateway.yml](v1/chatkit-gateway.yml) |
| Curator Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/curator-gateway.yml](v1/curator-gateway.yml) |
| Destructive Guardian Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/destructive-guardian-gateway.yml](v1/destructive-guardian-gateway.yml) |
| DNS API | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/dns.yml](v1/dns.yml) |
| Function Caller Service | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/function-caller.yml](v1/function-caller.yml) |
| Gateway | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/gateway.yml](v1/gateway.yml) |
| LLM Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/llm-gateway.yml](v1/llm-gateway.yml) |
| The Four Stars – Speech Atlas | 0.1.0 | Contexter alias Benedikt Eickhoff | [v1/the-four-stars-speech-atlas.yml](v1/the-four-stars-speech-atlas.yml) |
| OpenAPI Curator Service | 1.0.2 | Contexter alias Benedikt Eickhoff | [v1/openapi-curator.yml](v1/openapi-curator.yml) |
| Payload Inspection Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/payload-inspection-gateway.yml](v1/payload-inspection-gateway.yml) |
| Persistence Service | 1.0.2 | Contexter alias Benedikt Eickhoff | [v1/persist.yml](v1/persist.yml) |
| Planner Service | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/planner.yml](v1/planner.yml) |
| Planner Service (legacy alias) | 1.0.0 | Contexter alias Benedikt Eickhoff | [v0/planner.yml](v0/planner.yml) |
| Rate Limiter Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/rate-limiter-gateway.yml](v1/rate-limiter-gateway.yml) |
| Role Health Check Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/role-health-check-gateway.yml](v1/role-health-check-gateway.yml) |
| Security Sentinel Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/security-sentinel-gateway.yml](v1/security-sentinel-gateway.yml) |
| Semantic Browser & Dissector API | 0.2.1 | Contexter alias Benedikt Eickhoff | [v1/semantic-browser.yml](v1/semantic-browser.yml) |
| Tool Server | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/tool-server.yml](v1/tool-server.yml) |
| Tools Factory Service | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/tools-factory.yml](v1/tools-factory.yml) |

## Coverage Status

This section tracks ownership and adoption of Apple’s Swift OpenAPI Generator. See also the repository‑wide index at `../OPENAPI_COVERAGE.md`.

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
| `v1/chatkit-gateway.yml` | `FountainApps/gateway-server` (ChatKit plugin) | Manual router (plugin) | N/A |
| `v1/the-four-stars-speech-atlas.yml` | `FountainServiceKit-Persist` (ArcSpec surfaces) | Pending | Pending |


## Gateway Plugins

| Plugin | Owner | Status | Spec |
| --- | --- | --- | --- |
| Auth Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/auth-gateway.yml](v1/auth-gateway.yml) |
| Budget Breaker Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/budget-breaker-gateway.yml](v1/budget-breaker-gateway.yml) |
| Curator Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/curator-gateway.yml](v1/curator-gateway.yml) |
| ChatKit Gateway Plugin | Contexter alias Benedikt Eickhoff | ❌ | [v1/chatkit-gateway.yml](v1/chatkit-gateway.yml) |
| Destructive Guardian Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/destructive-guardian-gateway.yml](v1/destructive-guardian-gateway.yml) |
| LLM Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/llm-gateway.yml](v1/llm-gateway.yml) |
| Payload Inspection Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/payload-inspection-gateway.yml](v1/payload-inspection-gateway.yml) |
| Rate Limiter Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/rate-limiter-gateway.yml](v1/rate-limiter-gateway.yml) |
| Role Health Check Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/role-health-check-gateway.yml](v1/role-health-check-gateway.yml) |
| Security Sentinel Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/security-sentinel-gateway.yml](v1/security-sentinel-gateway.yml) |

## Persistence/FountainStore

| Service | Owner | Status | Spec |
| --- | --- | --- | --- |
| Persistence Service | Contexter alias Benedikt Eickhoff | ✅ | [v1/persist.yml](v1/persist.yml) |
| Speech Atlas (Four Stars) | Contexter alias Benedikt Eickhoff | ❌ | [v1/the-four-stars-speech-atlas.yml](v1/the-four-stars-speech-atlas.yml) |

## Linting

All specs must pass Redocly lint before commit. Use the per-spec matrix script to stay within rate limits:

```bash
# List available specs
Packages/FountainSpecCuration/openapi/lint-matrix.sh --list

# Lint a single spec
Packages/FountainSpecCuration/openapi/lint-matrix.sh persist

# Lint a batch
Packages/FountainSpecCuration/openapi/lint-matrix.sh auth-gateway bootstrap persist
```

The script defaults to stage `v1`. Pass `--stage v0` when working on legacy specs.

## Personas

The following personas drive Gateway plugin behaviour via the LLM:

- [Auth Gateway Persona](personas/auth.md) – [Spec](v1/auth-gateway.yml)
- [Rate Limiter Persona](personas/rate-limiter.md) – [Spec](v1/rate-limiter-gateway.yml)
- [Payload Inspection Persona](personas/payload-inspection.md) – [Spec](v1/payload-inspection-gateway.yml)
- [Security Sentinel Persona](personas/security-sentinel.md) – [Spec](v1/security-sentinel-gateway.yml)
- [Budget Breaker Persona](personas/budget-breaker.md) – [Spec](v1/budget-breaker-gateway.yml)
- [Destructive Guardian Persona](personas/destructive-guardian.md) – [Spec](v1/destructive-guardian-gateway.yml)
- [Role Health Check Persona](personas/role-health-check.md) – [Spec](v1/role-health-check-gateway.yml)
- [Persistence Service Persona](personas/persist.md) – [Spec](v1/persist.yml)
- [Local Agent Persona](personas/local-agent.md) – [Spec](v1/llm-gateway.yml)

### Default Roles

The Bootstrap Service seeds the following default roles, validated by the Role Health Check Gateway:

- [Drift Role](personas/drift.md) – [Spec](v1/bootstrap.yml)
- [Semantic Arc Role](personas/semantic-arc.md) – [Spec](v1/bootstrap.yml)
- [Patterns Role](personas/patterns.md) – [Spec](v1/bootstrap.yml)
- [History Role](personas/history.md) – [Spec](v1/bootstrap.yml)
- [View Creator Role](personas/view-creator.md) – [Spec](v1/bootstrap.yml)


© 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
