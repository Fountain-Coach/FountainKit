# AGENT — Studio (FountainLauncherUI) — DEPRECATED (Learnings)

Status: DEPRECATED — kept as a learnings artifact. No new features. Bug fixes only if they unblock builds.

Scope: This file applies to the entire `Packages/FountainApps/Sources/FountainLauncherUI/` subtree.
It captured the earlier Control workspace (three‑pane UI), OpenAPI editing pipeline, persona editor,
and diagnostics/merged logs. This implementation is superseded by the fresh Composer‑first app
(`composer-studio`).

Learnings snapshot (fixed; do not extend)

Composer‑first story (authoritative)
- Storyline: screenplay text (.fountain) → parsed model → mapped cue plans → applied notation → journal (+ UMP).
- States: No session → Source stored (ETag) → Parsed → Cued → Applied → Journaled.
- Guardrails: ETags for determinism, one‑click actions per state, visible results (warnings, counts, previews), journal timeline.

Change Now (scope of this agent)
- Introduce a Screenplay Session flow as default landing:
  - Create/select session; show current ETag and updated‑at.
  - Buttons: Parse → Map Cues → Apply, gated by preconditions.
  - Result cards: parse warnings, cue count, last render status, links to cue sheet/score.
  - Journal view: stored/parsed/cued/applied with anchors + timestamps.
- One readiness verdict: Keychain OK + valid Gateway URL + services healthy = Ready.
- Keep operator (start/stop/logs) and curator (OpenAPI edit) separate from composer flow.

## Studio System Introspection & Editing Plan (embedded)

What we keep from here
- Curated OpenAPI editing concepts (spec Save/Revert, Lint/Regenerate/Reload).
- Scripts for local dev and service lifecycle.
- Validator for curated spec list.

Testing & TDD
- Unit: spec curation mapping; routes diff; persona parser; memory compute; pane state.
- Integration: plugin generation invoked; reload called successfully.
- E2E: `Scripts/dev-up --check` → health → `/admin/routes` assert → `Scripts/dev-down`.

Direction of travel
- Use the new composer‑first app to surface the product story (session → ETag → parse → cues → apply → journal).
- Keep operator/curator tools as a separate space; do not re‑grow this legacy UI.

Curated specs source of truth (still valid for the repo)
- The curated OpenAPI list is declared in `Configuration/curated-openapi-specs.json`.
- Validation: `Scripts/validate-curated-specs.sh` checks that every curated path exists (and generator configs are present) and that all server specs are covered.
- CI runs the validator in both lint jobs; optionally install the local hook via `Scripts/install-git-hooks.sh` to run it pre‑commit.

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
