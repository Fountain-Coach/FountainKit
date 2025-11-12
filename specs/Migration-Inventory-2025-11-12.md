# Migration Inventory — 2025-11-12

What
- Initial inventory of server executables and service cores to support Phase 1 of the Migration Plan (Inventory & Classification). This list is derived from the current SwiftPM manifest and source tree.

Why
- Establish a concrete scope for service‑minimal adoption and subsequent MIDI‑2.0 agent transcoding.

How
- Source of truth: `Packages/FountainApps/Package.swift:1` and `Packages/FountainApps/Sources/**`.
- Classification keys: `pure-logic`, `light-state`, `external/heavy` (tentative; confirm in follow‑ups).

Servers (executables)
- gateway-server — tentative: external/heavy (LLM plugins, auth, policies). Sources: `Packages/FountainApps/Sources/gateway-server/*`
- pbvrt-server — tentative: pure-logic (compute demo) with light-state. Sources: `Packages/FountainApps/Sources/pbvrt-server/*`
- planner-server — tentative: pure-logic. Sources: `Packages/FountainApps/Sources/planner-server/*`
- function-caller-server — tentative: external/heavy (calls out to providers). Sources: `Packages/FountainApps/Sources/function-caller-server/*`
- persist-server — tentative: light-state. Sources: `Packages/FountainApps/Sources/persist-server/*`
- baseline-awareness-server — tentative: pure-logic. Sources: `Packages/FountainApps/Sources/baseline-awareness-server/*`
- bootstrap-server — tentative: light-state. Sources: `Packages/FountainApps/Sources/bootstrap-server/*`
- tools-factory-server — tentative: pure-logic. Sources: `Packages/FountainApps/Sources/tools-factory-server/*`
- tool-server — tentative: pure-logic. Sources: `Packages/FountainApps/Sources/tool-server/*`
- quietframe-service-server — tentative: light-state (UI‑adjacent). Sources: `Packages/FountainApps/Sources/quietframe-service-server/*`
- midi-service-server — tentative: light-state (transports/MIDI2). Sources: `Packages/FountainApps/Sources/midi-service-server/*`
- gateway-ci-smoke — test utility (not a service). Sources: `Packages/FountainApps/Sources/gateway-ci-smoke/*`

Service cores (OpenAPI generation owners)
- gateway-service — adopted. Config: `Packages/FountainApps/Sources/gateway-service/openapi-generator-config.yaml:1`
- pbvrt-service — present. Config: `Packages/FountainApps/Sources/pbvrt-service/openapi-generator-config.yaml:1`
- fountain-editor-service-core — adopted. Config: `Packages/FountainApps/Sources/fountain-editor-service/openapi-generator-config.yaml:1`
- patchbay-service — adopted. Config: `Packages/FountainApps/Sources/patchbay-service/openapi-generator-config.yaml:1`
- qc-mock-service — adopted. Config: `Packages/FountainApps/Sources/qc-mock-service/openapi-generator-config.yaml:1`

Next actions
- Confirm classifications with owners per service; annotate external dependencies explicitly.
- Ensure each server follows the service‑minimal pattern (core owns OpenAPI; server depends on core; no plugin in server).
- Add/store agent descriptors in FountainStore for public‑facing servers (gateway, planner, function‑caller, persist).
- Define PE mappings for 1–2 `pure-logic` services to kick off Phase 2 (MIDI‑2 agents), beginning with planner or baseline‑awareness.

