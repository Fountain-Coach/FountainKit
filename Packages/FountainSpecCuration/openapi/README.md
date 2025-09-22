# FountainAI OpenAPI Specifications

Versioned service definitions live here. Each YAML file describes a FountainAI service interface.
Persona definitions for Gateway plugins live in `personas/` and are referenced via `x-persona` in the specs.

- Every operation includes `x-fountain.visibility`, `x-fountain.reason`, and `x-fountain.allow-as-tool` extensions for curation.

For a repository-wide index of OpenAPI coverage, see [../OPENAPI_COVERAGE.md](../OPENAPI_COVERAGE.md).

| Service | Version | Owner | Spec |
| --- | --- | --- | --- |
| Auth Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/auth-gateway.yml](v1/auth-gateway.yml) |
| Baseline Awareness Service | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/baseline-awareness.yml](v1/baseline-awareness.yml) |
| Bootstrap Service | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/bootstrap.yml](v1/bootstrap.yml) |
| DNS API | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/dns.yml](v1/dns.yml) |
| Function Caller Service | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/function-caller.yml](v1/function-caller.yml) |
| Gateway | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/gateway.yml](v1/gateway.yml) |
| LLM Gateway | 2.0.0 | Contexter alias Benedikt Eickhoff | [v2/llm-gateway.yml](v2/llm-gateway.yml) |
| LLM Gateway | 2.0.0 | Contexter alias Benedikt Eickhoff | [v1/llm-gateway.yml](v1/llm-gateway.yml) |
| Persistence Service | 1.0.2 | Contexter alias Benedikt Eickhoff | [v1/persist.yml](v1/persist.yml) |
| Planner Service | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/planner.yml](v1/planner.yml) |
| Planner Service (legacy alias) | 1.0.0 | Contexter alias Benedikt Eickhoff | [v0/planner.yml](v0/planner.yml) |
| Role Health Check Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/role-health-check-gateway.yml](v1/role-health-check-gateway.yml) |
| Semantic Browser & Dissector API | 0.2.1 | Contexter alias Benedikt Eickhoff | [v1/semantic-browser.yml](v1/semantic-browser.yml) |
| Tools Factory Service | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/tools-factory.yml](v1/tools-factory.yml) |
| Rate Limiter Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/rate-limiter-gateway.yml](v1/rate-limiter-gateway.yml) |
| Payload Inspection Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/payload-inspection-gateway.yml](v1/payload-inspection-gateway.yml) |
| Budget Breaker Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/budget-breaker-gateway.yml](v1/budget-breaker-gateway.yml) |
| Destructive Guardian Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/destructive-guardian-gateway.yml](v1/destructive-guardian-gateway.yml) |
| Security Sentinel Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/security-sentinel-gateway.yml](v1/security-sentinel-gateway.yml) |
| Tool Server | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/tool-server.yml](v1/tool-server.yml) |
| OpenAPI Curator Service | 1.0.2 | Contexter alias Benedikt Eickhoff | [v1/openapi-curator.yml](v1/openapi-curator.yml) |
| Curator Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/curator-gateway.yml](v1/curator-gateway.yml) |
| Auth Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/auth-gateway.yml](v1/auth-gateway.yml) |
| Baseline Awareness Service | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/baseline-awareness.yml](v1/baseline-awareness.yml) |
| Bootstrap Service | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/bootstrap.yml](v1/bootstrap.yml) |
| DNS API | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/dns.yml](v1/dns.yml) |
| Function Caller Service | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/function-caller.yml](v1/function-caller.yml) |
| Gateway | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/gateway.yml](v1/gateway.yml) |
| Persistence Service | 1.0.2 | Contexter alias Benedikt Eickhoff | [v1/persist.yml](v1/persist.yml) |
| Planner Service | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/planner.yml](v1/planner.yml) |
| Role Health Check Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/role-health-check-gateway.yml](v1/role-health-check-gateway.yml) |
| Semantic Browser & Dissector API | 0.2.1 | Contexter alias Benedikt Eickhoff | [v1/semantic-browser.yml](v1/semantic-browser.yml) |
| Tools Factory Service | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/tools-factory.yml](v1/tools-factory.yml) |
| Rate Limiter Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/rate-limiter-gateway.yml](v1/rate-limiter-gateway.yml) |
| Payload Inspection Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/payload-inspection-gateway.yml](v1/payload-inspection-gateway.yml) |
| Budget Breaker Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/budget-breaker-gateway.yml](v1/budget-breaker-gateway.yml) |
| Destructive Guardian Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/destructive-guardian-gateway.yml](v1/destructive-guardian-gateway.yml) |
| Security Sentinel Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/security-sentinel-gateway.yml](v1/security-sentinel-gateway.yml) |
| Tool Server | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/tool-server.yml](v1/tool-server.yml) |
| OpenAPI Curator Service | 1.0.2 | Contexter alias Benedikt Eickhoff | [v1/openapi-curator.yml](v1/openapi-curator.yml) |
| Curator Gateway Plugin | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/curator-gateway.yml](v1/curator-gateway.yml) |


## Gateway Plugins

| Plugin | Owner | Status | Spec |
| --- | --- | --- | --- |
| Auth Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/auth-gateway.yml](v1/auth-gateway.yml) |
| Role Health Check Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/role-health-check-gateway.yml](v1/role-health-check-gateway.yml) |
| Rate Limiter Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/rate-limiter-gateway.yml](v1/rate-limiter-gateway.yml) |
| Payload Inspection Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/payload-inspection-gateway.yml](v1/payload-inspection-gateway.yml) |
| Budget Breaker Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/budget-breaker-gateway.yml](v1/budget-breaker-gateway.yml) |
| Destructive Guardian Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/destructive-guardian-gateway.yml](v1/destructive-guardian-gateway.yml) |
| Security Sentinel Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/security-sentinel-gateway.yml](v1/security-sentinel-gateway.yml) |
| Curator Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/curator-gateway.yml](v1/curator-gateway.yml) |
| Auth Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/auth-gateway.yml](v1/auth-gateway.yml) |
| Role Health Check Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/role-health-check-gateway.yml](v1/role-health-check-gateway.yml) |
| Rate Limiter Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/rate-limiter-gateway.yml](v1/rate-limiter-gateway.yml) |
| Payload Inspection Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/payload-inspection-gateway.yml](v1/payload-inspection-gateway.yml) |
| Budget Breaker Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/budget-breaker-gateway.yml](v1/budget-breaker-gateway.yml) |
| Destructive Guardian Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/destructive-guardian-gateway.yml](v1/destructive-guardian-gateway.yml) |
| Security Sentinel Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/security-sentinel-gateway.yml](v1/security-sentinel-gateway.yml) |
| Curator Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/curator-gateway.yml](v1/curator-gateway.yml) |
| LLM Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/llm-gateway.yml](v1/llm-gateway.yml) |

## Persistence/FountainStore

| Service | Owner | Status | Spec |
| --- | --- | --- | --- |
| Persistence Service | Contexter alias Benedikt Eickhoff | ✅ | [v1/persist.yml](v1/persist.yml) |
| Persistence Service | Contexter alias Benedikt Eickhoff | ✅ | [v1/persist.yml](v1/persist.yml) |

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

### Default Roles

The Bootstrap Service seeds the following default roles, validated by the Role Health Check Gateway:

- [Drift Role](personas/drift.md) – [Spec](v1/bootstrap.yml)
- [Semantic Arc Role](personas/semantic-arc.md) – [Spec](v1/bootstrap.yml)
- [Patterns Role](personas/patterns.md) – [Spec](v1/bootstrap.yml)
- [History Role](personas/history.md) – [Spec](v1/bootstrap.yml)
- [View Creator Role](personas/view-creator.md) – [Spec](v1/bootstrap.yml)


© 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
