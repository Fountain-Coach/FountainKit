# AudioTalk — Implementation Plan (FountainKit)

This plan adapts the AudioTalk vision (Drift–Pattern–Reflection) and upstream API contract to FountainKit’s modular workspace and OpenAPI‑first workflow.

Sources used:
- Upstream repo (reference): `External/AudioTalk` — spec/openapi.yaml, engineering guide, dev server
- Legacy narrative (reference): `External/AudioTalk-LegacyDocs` — vision PDF and status notes

Goals
- Provide a first‑class, modular AudioTalk service inside FountainKit that exposes a curated OpenAPI surface, streams MIDI 2.0, and integrates with Score/Engraving where available.
- Preserve “contract first” discipline: specs live in `FountainSpecCuration` and drive codegen via Swift OpenAPI Generator.

## Architecture Mapping (Drift–Pattern–Reflection)
- Drift (intent → plan)
  - Service parses phrases to a typed plan and maintains a vocabulary/macro dictionary.
  - Inputs may originate from LLMs or rule macros; representation lives in `FountainCore` shared types.
- Pattern (rules → authority)
  - Engraving/Score rules provide authoritative grouping/spacing/notation transforms (consumed via adapters).
  - Keep rule evaluation outside service target; import via `FountainCore` abstractions or dedicated adapters.
- Reflection (verify → improve)
  - Close the loop with visual snapshots (via ScoreKit bridges when available), UMP traces, and plan diffs.

## Deliverables (by phase)

Phase 0 — Spec curation and parity (P0)
- Add curated spec `Packages/FountainSpecCuration/openapi/v1/audiotalk.yml` seeded from upstream `External/AudioTalk/spec/openapi.yaml`.
- Expand with schemas for: `DictionaryItem`, `MacroItem`, `Plan`, `Token`, `NotationSession`, `RenderResponse`, and `UMPBatch`.
- Add `lint-matrix` entries; CI must lint and validate schemas. No generated sources committed.

Phase 1 — Service package scaffold (P0)
- New package `Packages/FountainServiceKit-AudioTalk` with target `AudioTalkService`.
- Include `Sources/AudioTalkService/openapi.yaml` as a symlink to curated spec and `openapi-generator-config.yaml` with `generate: [types, server]`.
- Add minimal handler shims conforming to generated server protocol (return stubs) and register transport via `FountainCore` server glue.

Phase 2 — Telemetry + MIDI streaming (P0)
- Integrate `FountainTelemetryKit` to accept/send UMP batches.
- Provide a streaming transport: SSE over MIDI (`SSEOverMIDI`) for previews; define `/ump/{session}/send` semantics and backpressure.

Phase 3 — Drift engine (P1)
- Implement phrase tokenizer + normalizer; produce typed `Plan` with op graph (insert motif, articulation, dynamics, tempo changes).
- Macro store: CRUD + promotion path; persist via `FountainServiceKit-Persist` (if available) behind `FountainCore` store client.

Phase 4 — Pattern adapters (P1)
- Define adapters to Engraving/Score transforms (grouping/spacing/accidental, ties, beam groups) with explicit inputs/outputs.
- Keep adapters optional; degrade gracefully when renderer not present.

Phase 5 — Reflection loop (P2)
- Snapshot API: request preview artifacts (PNG/SVG) and UMP traces; compare A/B and annotate diffs.
- Plan critique endpoint: return structured improvement hints and affected measure/beat indices.

Phase 6 — Gateway + Apps (P2)
- Gateway orchestration: add an AudioTalk persona plugin in `FountainGatewayKit` that wires phrase→plan→apply→preview.
- Executables in `FountainApps`:
  - `audiotalk-server` — NIO server using generated handlers.
  - `audiotalk-cli` — local testing client (wraps generated client; prints diffs/snapshots URIs).

## OpenAPI Surface (initial)
- `GET /dictionary` → list tokens/mappings
- `POST /dictionary` → upsert token(s)
- `POST /intent` → phrase → `Plan`
- `POST /intent/apply` → apply `Plan` atomically (idempotent)
- `GET/POST /macros` → list/create macros from plans
- `POST /lesson/ab` → A/B ear‑training prompt
- `POST /notation/sessions` → create session
- `PUT/GET /notation/{id}/score` → LilyPond source
- `POST /notation/{id}/render` → render artifacts
- `POST /ump/{session}/send` → accept UMP batch (MIDI 2.0)

Notes
- Curate schemas (nullable, enums, bounds) and error models (`Problem+json`).
- Add tags for `dictionary`, `intent`, `notation`, `midi`, `reflection`.

## Package Layout (proposed)
- `Packages/FountainServiceKit-AudioTalk/`
  - `Package.swift` (alphabetised deps)
  - `Sources/AudioTalkService/` — service logic + adapters
  - `Sources/AudioTalkService/openapi.yaml` (symlink to curated spec)
  - `Sources/AudioTalkService/openapi-generator-config.yaml`
  - `Tests/AudioTalkServiceTests/` — unit + golden tests
- `Packages/FountainApps/Sources/audiotalk-server/` — executable harness
- `Packages/FountainApps/Sources/audiotalk-cli/` — smoke client

## Testing & CI
- Unit tests: tokenizer, plan builder, UMP batch validation, Lily score CRUD.
- Golden fixtures: plan JSON, UMP traces, Lily snippets.
- Snapshot tests (optional): PNG/SVG if renderer available; guarded by feature flags.
- CI: add to build matrix; ensure OpenAPI lint + full `swift build` green; no generated sources committed.

## Risks & Controls
- Renderer availability: feature‑flag rendering; make endpoints return 501 when disabled.
- Schema drift: treat curated spec as authoritative; upstream spec tracked for parity notes.
- Performance: budget for UMP batching and backpressure (JR timestamps, host‑time mapping in TelemetryKit).

## Milestone Checklist (P0 → P2)
- [ ] Curated spec added and linted
- [ ] Service package skeleton compiles with generated server stubs
- [ ] MIDI UMP endpoint wired to TelemetryKit
- [ ] Drift tokenizer + typed plan v0
- [ ] Macro CRUD + persistence behind FountainCore store
- [ ] Reflection endpoints return stubs with structure
- [ ] Gateway persona and server/CLI executables

## Next Actions (this repo)
1) Add curated spec file under `Packages/FountainSpecCuration/openapi/v1/audiotalk.yml` seeded from upstream.
2) Scaffold `FountainServiceKit-AudioTalk` with generator config and empty handlers.
3) Add `audiotalk-server` executable stub that exposes health and routes to generated server.
4) Wire TelemetryKit UMP endpoint; return 202 Accepted and validate payload.
5) Land basic unit tests and CI lint for the new spec.

