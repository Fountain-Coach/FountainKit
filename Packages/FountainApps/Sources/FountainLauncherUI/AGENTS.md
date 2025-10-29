# AGENT — Studio (FountainLauncherUI) — DEPRECATED (learnings)

What: FountainLauncherUI is the frozen snapshot of the original control workspace UI. It wrapped launcher scripts, exposed a curated OpenAPI editor, persona editor, and merged logs/diagnostics in a three‑pane layout. The active product now is `composer-studio`.

Why it remains: to preserve lessons and keep builds green when needed. Do not add features; only fix issues that break compilation or tests.

How (if you must run it): build and run with SwiftPM. It’s macOS‑only and expects Keychain‑backed secrets (no `.env`). The app reads `LAUNCHER_SIGNATURE` from Keychain with a default and may require `OPENAI_API_KEY` in Keychain (service `FountainAI`, account `OPENAI_API_KEY`).
- Build: `swift build --package-path Packages/FountainApps -c debug --target FountainLauncherUI`
- Run: `swift run --package-path Packages/FountainApps FountainLauncherUI`
- Tests: `swift test --package-path Packages/FountainApps -c debug --filter FountainLauncherUITests`

Where code lives
- App entry and views: `Packages/FountainApps/Sources/FountainLauncherUI/LauncherUIApp.swift`
- Resource resolution: `Packages/FountainApps/Sources/FountainLauncherUI/LauncherResources.swift`
- Tests: `Packages/FountainApps/Tests/FountainLauncherUITests`

Composer‑first remains authoritative: screenplay text (.fountain) → parsed model → cue plans → applied notation → journal (+ UMP). Sessions move deterministically “stored (ETag) → parsed → cued → applied → journaled”, and each step surfaces explainable results (warnings, counts, previews) in a visible timeline.

Keep ideas, not UI
Retain the curated OpenAPI editing loop (Save/Revert, Lint/Regenerate/Reload), the local dev lifecycle (`Scripts/dev/**`), and the curated‑list validator — but keep operator/curator tools separate from the composer flow. Do not rebuild this legacy surface.

Testing focus
Favor behavior over chrome. Unit: curated spec mapping, routes diff, persona parsing, memory compute, pane state. Integration: generator plugins run and gateway reload succeeds. E2E: `Scripts/dev-up --check` → probe health → assert `/admin/routes` contains the minimal set → `Scripts/dev-down`.

Curated OpenAPI list
Declared in `Configuration/curated-openapi-specs.json`. Validate with `Scripts/openapi/validate-curated-specs.sh` (checks paths and generator configs). Optionally install `Scripts/install-git-hooks.sh` to run it pre‑commit. CI lint jobs run the validator and expect no generated sources in VCS.

Scope if you must touch this code
Limit to: curated OpenAPI panel (list specs, Save/Revert, lint, regenerate via `swift build`, reload routes), routes viewer (`/admin/routes` diff pre/post), persona editor (`Configuration/persona.yaml` with “effective persona” preview), logs/services (follow‑tail, filters), and profile selection (default Full with correct health endpoint). Add tests alongside each change.
