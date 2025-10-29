# AGENT — Composer Studio (fresh app)

What: Composer Studio is the composer‑first UI that replaces the legacy FountainLauncherUI. The source of truth is screenplay text (.fountain) with inline tags; sessions move deterministically “stored (ETag) → parsed model → cue plans → applied notation → journaled (+ UMP)”. The app is OpenAPI‑first, reproducible, and secured via Keychain where needed.

Why: to make changes explainable, reproducible, and safe. Deterministic ETags + a readable journal enable Apply/Undo/Try, previews, and compact diffs you can trust.

How to run
- Build: `swift build --package-path Packages/FountainApps -c debug --target composer-studio`
- Run: `swift run --package-path Packages/FountainApps composer-studio`
- Tests: `swift test --package-path Packages/FountainApps -c debug --filter ComposerStudio` (UI snapshot tests live under `Packages/FountainApps/Tests/*UITests`)

Where code lives
- App entry/views: `Packages/FountainApps/Sources/composer-studio/ComposerStudioApp.swift`
- Chat/UI: `Packages/FountainApps/Sources/composer-studio/ChatView.swift`, `ChatModels.swift`, `PlanPreviewCard.swift`
- Design source: `Design/composer-studio-first-open.svg`, `Design/composer-studio-after-analyze.svg`

Interaction model
Chat and direct manipulation sit side‑by‑side. Chat examples: “soften strings after Scene 2”, “apply gentle mood in the intro”. The assistant responds with a short plan and preview, offering Apply, Try (temporary), and Undo. The screenplay editor provides a tag palette, inline lint/fix, and clickable anchors from chat back into text. Previews are immediate; the journal is a readable, explainable timeline — not logs.

MVP scope
Show a session strip (ID, ETag, Updated‑at), an actions row (Parse → Map Cues → Apply) gated by preconditions, and results panels per action (parse warnings; cue count + preview; apply render status + score link). The journal anchors stored/parsed/cued/applied with timestamps. Next, place chat beside the editor with slash commands (/analyze, /map, /apply, /render, /export), compact diffs/anchors in assistant messages, and a small state bar (Project • Scene • Selection • Tempo/Key).

Operator controls (start/stop/logs) remain in scripts; OpenAPI curation stays in the control/curator surface. MVP acceptance: same input ETag ⇒ same model/cues/apply; journal persists events with timestamps/anchors. For MVP+Chat: NL drives parse/map/apply with previews; Apply/Undo idempotent per ETag; “Try” never mutates stored score; warnings include in‑place “Fix”.

Design is SVG‑first
Update `Design/` SVGs as the source of truth. Edit layout/typography in the SVGs (annotate sizes and fonts), then implement SwiftUI to match exactly. Acceptance is visual parity within ±4 px and specified fonts; chat anchors at the bottom; preview behavior follows SVG notes. Any UI change must first update the SVG; PRs without SVG updates are rejected for layout changes.

Testing
Focus on state gating, parse→map coupling, and journal rendering. Integration runs parse/map/apply against local services. UI surfaces use snapshot tests with golden baselines; rebaseline with `Scripts/ci/ui-rebaseline.sh` only after numeric invariants pass.
