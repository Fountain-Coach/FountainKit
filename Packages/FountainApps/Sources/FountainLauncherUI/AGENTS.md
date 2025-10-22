# AGENT — Studio (FountainLauncherUI) System Introspection & Editing

Scope: This file applies to the entire `Packages/FountainApps/Sources/FountainLauncherUI/` subtree.
It governs the Control workspace (three‑pane UI), OpenAPI editing pipeline, persona editor,
and diagnostics/merged logs.

Authoritative plan (embedded)

## Studio System Introspection & Editing Plan (embedded)

M0 — Stabilize & Trim
- Default: Full Fountain; one Control workspace (three panes).
- Curated API set only; persist pane widths; Follow‑Tail for logs.

M1 — Context Hub (Right Pane)
- Segments: OpenAPI | Routes | Services | Persona | Memory.
- OpenAPI editor (Save/Revert, Lint/Regenerate/Reload). Routes viewer + diff.
- Services: aggregated live tails; Persona: edit `Configuration/persona.yaml` and compute effective persona.
- Memory: query Journal/Dictionary/Macros/Anchors; compute snapshot.

M2 — OpenAPI E2E: lint → generate → build → reload (diff in UI).

M3 — Persona & Assistant: YAML↔model round‑trip; apply hooks where relevant.

M4 — Semantic Memory: deterministic snapshot from fixtures.

M5 — Diagnostics: merged logs + filters; health timeline.

M6 — Profiles: Full default; subsets as experiments; persist selection.

M7 — Perf/Hygiene: precompile flows; quiet SPM warnings.

M8 — QA/CI: smoke E2E on every change; coverage report.

Testing & TDD
- Unit: spec curation mapping; routes diff; persona parser; memory compute; pane state.
- Integration: plugin generation invoked; reload called successfully.
- E2E: `Scripts/dev-up --check` → health → `/admin/routes` assert → `Scripts/dev-down`.

Principles
1) Full stack by default. AudioTalk‑only is for experiments.
2) OpenAPI‑first. Curated finite spec list only — no directory scans.
3) TDD for logic. Each feature ships with tests.
4) One Control workspace (Left: principal; Middle: logs; Right: OpenAPI/Routes/Services/Persona/Memory).

What to do here
- Curated OpenAPI panel
  - List the core specs; allow edit (Save/Revert), `lint`, `regenerate` (swift build), `reload routes`.
  - Add tests for curated path mapping and regeneration triggers.
- Routes viewer
  - Fetch `/admin/routes`, filter, and diff pre/post reload. Tests cover diff engine.
- Persona editor
  - Edit `Configuration/persona.yaml`; show “effective persona”. Tests for YAML ↔ model round‑trip.
- Logs & services
  - Add Follow‑tail, merged logs, filters. Tests for filter correctness.
- Profiles
  - Default Full; persist setting; use correct health endpoint.

Testing requirements (enforced)
- Unit tests: curated spec mapping; routes diff; persona parser; log filter.
- Integration: generator plugins invoked via build; gateway reload handler called.
- E2E smoke: `Scripts/dev-up --check` → health → `/admin/routes` contains minimal set → `Scripts/dev-down`.

CI
- Lint + build + tests must pass. No generated sources in VCS. Warn on added scans.
