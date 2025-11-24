# FountainAI OpenAPI Specifications

Versioned service definitions live here. Each YAML file describes a FountainAI service interface.
Persona definitions for Gateway plugins live in `personas/` and are referenced via `x-persona` in the specs.

- Every operation includes `x-fountain.visibility`, `x-fountain.reason`, and `x-fountain.allow-as-tool` extensions for curation.

For a repository‑wide index of OpenAPI coverage and adoption status, see [../OPENAPI_COVERAGE.md](../OPENAPI_COVERAGE.md).

### Recent Updates

- 2025-10-20 – Added Linux workspace `swift build` guardrail and ChatKit smoke harness powered by the generated `GatewayAPI` client (`Scripts/ci-smoke.sh`, `Packages/FountainApps/Sources/gateway-ci-smoke`).
- 2025-10-16 – Documented SSE incremental token framing for the ChatKit message stream (`v1/gateway.yml`).
- 2025-10-16 – Added tool call streaming events to the ChatKit gateway spec (`v1/gateway.yml`).
- 2025-10-16 – Aligned ChatKit session, thread, and attachment specs; added generator coverage for plugin routes (`v1/gateway.yml`, `v1/chatkit-gateway.yml`).

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
| LLM Chat Instrument | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/llm-chat.yml](v1/llm-chat.yml) |
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
| AudioTalk Service | 0.1.0 | Contexter alias Benedikt Eickhoff | [v1/audiotalk.yml](v1/audiotalk.yml) |
| Instrument Sketch Service (PatchBay) | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/patchbay.yml](v1/patchbay.yml) |
| MIDI Service | 0.1.0 | Contexter alias Benedikt Eickhoff | [v1/midi-service.yml](v1/midi-service.yml) |
| Prompt‑Bound VRT API | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/pb-vrt.yml](v1/pb-vrt.yml) |
| Composer Score Service | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/composer-score.yml](v1/composer-score.yml) |
| Composer Script Service | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/composer-script.yml](v1/composer-script.yml) |
| Composer Cues Service | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/composer-cues.yml](v1/composer-cues.yml) |
| Instrument Lint Service | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/instrument-lint.yml](v1/instrument-lint.yml) |
| Instrument New Service | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/instrument-new.yml](v1/instrument-new.yml) |
| SVG Animation Renderer Instrument | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/svg-animation.yml](v1/svg-animation.yml) |
| Teatro Prompt Factory | 1.0.0 | Contexter alias Benedikt Eickhoff | [v1/teatro-prompt-factory.yml](v1/teatro-prompt-factory.yml) |
| Teatro Game Engine Core | 0.1.0 | Contexter alias Benedikt Eickhoff | [v1/teatro-game-engine-core.yml](v1/teatro-game-engine-core.yml) |
| Teatro Engine Profile Service | 0.1.0 | Contexter alias Benedikt Eickhoff | [v1/teatro-engine-profile.yml](v1/teatro-engine-profile.yml) |
| Bullet Physics Engine Service | 0.1.0 | Contexter alias Benedikt Eickhoff | [v1/bullet-physics.yml](v1/bullet-physics.yml) |
| Teatro Rendering Service | 0.1.0 | Contexter alias Benedikt Eickhoff | [v1/teatro-rendering.yml](v1/teatro-rendering.yml) |
| Teatro Input Service | 0.1.0 | Contexter alias Benedikt Eickhoff | [v1/teatro-input.yml](v1/teatro-input.yml) |
| Teatro Assets Service | 0.1.0 | Contexter alias Benedikt Eickhoff | [v1/teatro-assets.yml](v1/teatro-assets.yml) |
| Teatro Audio Service | 0.1.0 | Contexter alias Benedikt Eickhoff | [v1/teatro-audio.yml](v1/teatro-audio.yml) |
| Teatro Scripting Service | 0.1.0 | Contexter alias Benedikt Eickhoff | [v1/teatro-scripting.yml](v1/teatro-scripting.yml) |
| Teatro Stage Puppet Service | 0.1.0 | Contexter alias Benedikt Eickhoff | [v1/teatro-stage-puppet.yml](v1/teatro-stage-puppet.yml) |

## Coverage Status

This section tracks ownership and adoption of Apple’s Swift OpenAPI Generator. See also the repository‑wide index at `../OPENAPI_COVERAGE.md`.

| Spec | Owner target(s) | Server adoption | Client adoption |
| --- | --- | --- | --- |
| `v1/gateway.yml` | `FountainApps/gateway-server` | Generator enabled (control plane + ChatKit plugin) | `FountainAPIClients/GatewayAPI` generator enabled (CI smoke) |
| `v1/chatkit-gateway.yml` | `FountainApps/gateway-server` (ChatKit plugin) | Generator enabled (plugin handlers) | N/A |
| `v1/baseline-awareness.yml` | `FountainServiceKit-Awareness/AwarenessService` | Generator enabled | `FountainAPIClients/AwarenessAPI` generator enabled |
| `v1/fk-ops.yml` | `FountainServiceKit-FKOps/FKOpsService` | Generator enabled | `FountainAPIClients/FKOpsAPI` generator enabled |
| `v1/semantic-browser.yml` | `FountainServiceKit-SemanticBrowser/SemanticBrowserService` | Generator enabled | `FountainAPIClients/SemanticBrowserAPI` generator enabled |
| `v1/persist.yml` | `FountainServiceKit-Persist/PersistService` | Generator enabled | `FountainAPIClients/PersistAPI` generator enabled |
| `v1/the-four-stars-speech-atlas.yml` | `FountainServiceKit-Persist/SpeechAtlasService` | Generator enabled | `FountainAPIClients/SpeechAtlasAPI` generator enabled |
| `v1/planner.yml` | `FountainServiceKit-Planner/PlannerService` | Generator enabled | `FountainAPIClients/PlannerAPI` generator enabled |
| `v1/function-caller.yml` | `FountainServiceKit-FunctionCaller/FunctionCallerService` | Generator enabled | `FountainAPIClients/FunctionCallerAPI` generator enabled |
| `v1/bootstrap.yml` | `FountainServiceKit-Bootstrap/BootstrapService` | Generator enabled | `FountainAPIClients/BootstrapAPI` generator enabled |
| `v1/tools-factory.yml` | `FountainServiceKit-ToolsFactory/ToolsFactoryService` | Generator enabled | `FountainAPIClients/ToolsFactoryAPI` generator enabled |
| `v1/tool-server.yml` | `FountainServiceKit-ToolServer/ToolServerService` | Generator enabled | Pending (no dedicated client target) |
| `v1/dns.yml` | (Gateway DNS management) | Not wired to a Swift target | `FountainAPIClients/DNSAPI` generator enabled |
| `v1/llm-gateway.yml` | Gateway plugin (no standalone server) | Manual plugin, generator not configured | `FountainAPIClients/LLMGatewayAPI` generator enabled |
| `v1/openapi-curator.yml` | `FountainTooling/openapi-curator-service` | Pending | Pending |
| `v1/audiotalk.yml` | `FountainServiceKit-AudioTalk/AudioTalkService` | Pending | Pending |
| `v1/audiotalk.yml` | `FountainServiceKit-AudioTalk/AudioTalkService` | Generator configured (types, server stubs pending) | `FountainAPIClients/AudioTalkAPI` generator enabled |


## Gateway Plugins

| Plugin | Owner | Status | Spec |
| --- | --- | --- | --- |
| Auth Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/auth-gateway.yml](v1/auth-gateway.yml) |
| Budget Breaker Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/budget-breaker-gateway.yml](v1/budget-breaker-gateway.yml) |
| Curator Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/curator-gateway.yml](v1/curator-gateway.yml) |
| ChatKit Gateway Plugin | Contexter alias Benedikt Eickhoff | ✅ | [v1/chatkit-gateway.yml](v1/chatkit-gateway.yml) |
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
