# AGENT — Composer Studio (fresh app)

Scope: `Packages/FountainApps/Sources/composer-studio/` — new composer‑first UI.
Status: ACTIVE. This replaces the deprecated `FountainLauncherUI` for product work.

Story (authoritative)
- Screenplay text (.fountain) with inline tags is the source of truth.
- States: Source stored (ETag) → Parsed model → Cue plans → Applied notation → Journaled (+ UMP).
- Deterministic, reproducible, secure (Keychain), OpenAPI‑first.

MVP (Change Now)
- Session strip at top (ID, ETag, Updated‑at). Create/select.
- Actions row (Parse → Map Cues → Apply) gated by preconditions.
- Results panels:
  - Parse: model summary + warnings.
  - Map: cue count + preview.
  - Apply: render status + score preview link.
- Journal timeline at bottom (stored/parsed/cued/applied with anchors).

Non‑goals (here)
- Operator controls (start/stop/logs) — keep in scripts.
- OpenAPI curation — remains in Control/curator space.

Acceptance (MVP)
- Same input (ETag) → same outputs (model/cues/apply) with cache hits visible.
- Journal events persisted and visible in order with timestamps/anchors.

Testing
- Unit: state gating, parse→map coupling, journal rendering.
- Integration: parse/map/apply round‑trip using local services.

