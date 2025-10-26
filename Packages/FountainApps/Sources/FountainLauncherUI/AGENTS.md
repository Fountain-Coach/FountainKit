# AGENT — Studio (FountainLauncherUI) — DEPRECATED (learnings)

FountainLauncherUI is a frozen snapshot of the original Control workspace. It covered the three‑pane UI for services, a curated OpenAPI editor, a persona editor, and merged logs/diagnostics. The active product path is the composer‑first app (`composer-studio`); this code remains only to preserve lessons and to unblock builds when needed. Do not add features here; fix only what breaks compilation or tests.

The composer‑first story remains authoritative: screenplay text (.fountain) becomes a parsed model, then mapped cue plans, then applied notation, and finally a journal (with UMP). Sessions move deterministically through the states “stored (ETag) → parsed → cued → applied → journaled”, and each step exposes visible results (warnings, counts, previews) in a timeline you can explain.

What we keep from this codebase are ideas, not UI: the curated OpenAPI editing loop (Save/Revert, Lint/Regenerate/Reload), the local dev lifecycle scripts, and the curated‑list validator. When you need the operator or curator tools, keep them separate from the composer flow — don’t re‑grow this legacy surface.

Testing should focus on the underlying behaviors rather than view chrome. Unit tests cover curated spec mapping, route diffs, persona parsing, memory compute, and pane state; integration tests make sure generator plugins run and a reload hits the gateway; E2E smoke brings the stack up with `Scripts/dev-up --check`, probes health, asserts `/admin/routes` contains the minimal set, and tears down with `Scripts/dev-down`.

The curated OpenAPI list for the repo is declared in `Configuration/curated-openapi-specs.json`. Validate with `Scripts/validate-curated-specs.sh` (it checks that paths exist and generator configs are present) and optionally install `Scripts/install-git-hooks.sh` to run it pre‑commit. CI runs the validator in lint jobs and expects no generated sources in VCS; warn on added scans.

If you must touch this area, keep the scope tight: the curated OpenAPI panel (list specs, Save/Revert, lint, regenerate via swift build, reload routes), a routes viewer (`/admin/routes` diff pre/post reload), the persona editor (`Configuration/persona.yaml` with an “effective persona” preview), logs/services (follow‑tail and filters), and profile selection (default Full with the correct health endpoint). Add tests alongside each.
